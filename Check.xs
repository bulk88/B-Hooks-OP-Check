#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

/* we use the polyfill newSV_type|5.009005|5.003007 if req */
#include "ppport.h"

#if PERL_BCDVERSION < 0x5010001
typedef unsigned Optype;
#endif /* <5.10.1 */

#ifndef SvIOK_nog
#	define SvIOK_nog(sv) ((SvFLAGS(sv) & (SVf_IOK|SVs_GMG)) == SVf_IOK)
#endif

/*	fix https://github.com/Perl/perl5/issues/22653
		dont call the Perl_sv_2uv() getter fnc for "SvUV"s missing their
		SVf_IVisUV flag, that have no magic, are IOK-on, and same bitpattern as IVs.
*/

#define SvUV_fixed2uv(sv) (SvIOK_nog(sv) ? SvUVX(sv) : sv_2uv(sv))

#ifndef wrap_op_checker
# define wrap_op_checker(c,n,o) THX_wrap_op_checker(aTHX_ c,n,o)
static void THX_wrap_op_checker(pTHX_ Optype opcode,
	Perl_check_t new_checker, Perl_check_t *old_checker_p)
{
	if(*old_checker_p) return;
	OP_REFCNT_LOCK;
	if(!*old_checker_p) {
		*old_checker_p = PL_check[opcode];
		PL_check[opcode] = new_checker;
	}
	OP_REFCNT_UNLOCK;
}
#endif /* !wrap_op_checker */

#include "hook_op_check.h"

STATIC Perl_check_t orig_PL_check[OP_max];
STATIC AV *check_cbs[OP_max];

#define run_orig_check(type, op) (CALL_FPTR (orig_PL_check[(type)])(aTHX_ op))

STATIC void *
S_bhoc_get_mg_ptr (pTHX_ SV *sv) {
	MAGIC *mg;

	PERL_UNUSED_CONTEXT;
	if ((mg = mg_find (sv, PERL_MAGIC_ext))) {
		return mg->mg_ptr;
	}

	return NULL;
}
#define get_mg_ptr(_sv) S_bhoc_get_mg_ptr (aTHX_ _sv)

STATIC OP *
check_cb (pTHX_ OP *op) {
	SSize_t i;
	SSize_t avlen;
	AV *hooks = check_cbs[op->op_type];
	OP *ret = run_orig_check (op->op_type, op);

	if (!hooks) {
		return ret;
	}

	avlen = av_len (hooks);
	for (i = 0; i <= avlen; i++) {
		hook_op_check_cb cb;
		void *user_data;
		SV **hook = av_fetch (hooks, i, 0);

		if (!hook || !*hook) {
			continue;
		}

		user_data = get_mg_ptr (*hook);

		cb = INT2PTR (hook_op_check_cb, SvUV_fixed2uv(*hook));
		ret = CALL_FPTR (cb)(aTHX_ ret, user_data);
	}

	return ret;
}

hook_op_check_id
hook_op_check (opcode type, hook_op_check_cb cb, void *user_data) {
	dTHX;
	AV *hooks;
	SV *hook;

	hooks = check_cbs[type];

	if (!hooks) {
		hooks = newAV ();
		check_cbs[type] = hooks;
		wrap_op_checker(type, check_cb, &orig_PL_check[type]);
	}

	hook = newSV_type(SVt_PVMG); /* prevent sv_upgrade in sv_magic */
	SvIOK_on(hook); /* new and empty inline sv_setuv() skip old data logic */
	SvUV_set(hook, PTR2UV (cb));
	if (! (PTR2UV (cb) <= (UV)IV_MAX) )
		SvIsUV_on(hook);
	SvTAINT(hook);
	sv_magic (hook, NULL, PERL_MAGIC_ext, (const char *)user_data, 0);
	av_push (hooks, hook);

	return (hook_op_check_id)PTR2UV (hook);
}

void *
hook_op_check_remove (opcode type, hook_op_check_id id) {
	dTHXa(NULL);;
	AV *hooks;
	SSize_t i;
	SSize_t avlen;
	void *ret = NULL;

	hooks = check_cbs[type];

	if (!hooks) {
		return NULL;
	}

	aTHXa(PERL_GET_THX);
	avlen = av_len (hooks);
	for (i = 0; i <= avlen; i++) {
		SV **hook = av_fetch (hooks, i, 0);

		if (!hook || !*hook) {
			continue;
		}

		if ((hook_op_check_id)PTR2UV (*hook) == id) {
			ret = get_mg_ptr (*hook);
			av_delete (hooks, i, G_DISCARD);
		}
	}

	return ret;
}

MODULE = B::Hooks::OP::Check  PACKAGE = B::Hooks::OP::Check

PROTOTYPES: DISABLE
