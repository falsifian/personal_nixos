#! @perl@ -w -I@libDir@ -I@readline@

use strict;
use Machine;
use Term::ReadLine;

$SIG{PIPE} = 'IGNORE'; # because Unix domain sockets may die unexpectedly

$ENV{PATH} = "@extraPath@:$ENV{PATH}";

STDERR->autoflush(1);

my %vms;
my $context = "";


foreach my $vmScript (@ARGV) {
    my $vm = Machine->new({startCommand => $vmScript});
    $vms{$vm->name} = $vm;
    $context .= "my \$" . $vm->name . " = \$vms{'" . $vm->name . "'}; ";
}


sub startAll {
    $_->start foreach values %vms;
}


sub runTests {
    if (defined $ENV{tests}) {
        eval "$context $ENV{tests}";
        die $@ if $@;
    } else {
        my $term = Term::ReadLine->new('nixos-vm-test');
        $term->ReadHistory;
        while (defined ($_ = $term->readline("> "))) {
            eval "$context $_\n";
            warn $@ if $@;
        }
        $term->WriteHistory;
    }

    # Copy the kernel coverage data for each machine, if the kernel
    # has been compiled with coverage instrumentation.
    foreach my $vm (values %vms) {
        my $gcovDir = "/sys/kernel/debug/gcov";

        next unless $vm->isUp();

        my ($status, $out) = $vm->execute("test -e $gcovDir");
        next if $status != 0;

        # Figure out where to put the *.gcda files so that the report
        # generator can find the corresponding kernel sources.
        my $kernelDir = $vm->mustSucceed("echo \$(dirname \$(readlink -f /var/run/current-system/kernel))/.build/linux-*");
        chomp $kernelDir;
        my $coverageDir = "/hostfs" . $vm->stateDir() . "/coverage-data/$kernelDir";

        # Copy all the *.gcda files.
        $vm->execute("for d in $gcovDir/nix/store/*/.build/linux-*; do for i in \$(cd \$d && find -name '*.gcda'); do echo \$i; mkdir -p $coverageDir/\$(dirname \$i); cp -v \$d/\$i $coverageDir/\$i; done; done");
    }
}


# Create an empty qcow2 virtual disk with the given name and size (in
# MiB).
sub createDisk {
    my ($name, $size) = @_;
    system("qemu-img create -f qcow2 $name ${size}M") == 0
        or die "cannot create image of size $size";
}


END {
    foreach my $vm (values %vms) {
        if ($vm->{pid}) {
            print STDERR "killing ", $vm->{name}, " (pid ", $vm->{pid}, ")\n";
            kill 9, $vm->{pid};
        }
    }
}


runTests;
