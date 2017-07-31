use strict;
use warnings;

use lib 'inc';
use ExtUtils::MakeMaker::Dist::Zilla::Develop;

use ExtUtils::Depends 0.302;

# keep this code consistent with the [MakeMaker::Awesome] arguments in dist.ini
my $pkg = ExtUtils::Depends->new('B::Hooks::OP::Check');
$pkg->install('hook_op_check.h');
$pkg->add_xs('Check.xs');
$pkg->add_pm('lib/B/Hooks/OP/Check.pm' => '$(INST_LIB)/B/Hooks/OP/Check.pm');

mkdir 'build';
$pkg->save_config('build/IFiles.pm');

WriteMakefile(
    NAME => 'B::Hooks::OP::Check',
    VERSION_FROM => 'lib/B/Hooks/OP/Check.pm',
    INSTALLMAN1DIR => 'none',
    INSTALLMAN3DIR => 'none',
    NORECURS => 1,
    $pkg->get_makefile_vars,
    FUNCLIST => [qw/hook_op_check hook_op_check_remove/],
    DL_FUNCS => { 'B::Hooks::OP::Check' => [] },
);

use Devel::PPPort;
Devel::PPPort::WriteFile();
system("$^X ppport.h --compat-version=5.008001 --quiet *.xs *.[hc]");
