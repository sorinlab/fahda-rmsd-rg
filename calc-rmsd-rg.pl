#!/usr/bin/perl

use strict;
use warnings;

use Cwd;
use FindBin qw($Bin);
use Getopt::Long qw(HelpMessage :config pass_through);
use lib "$Bin/../lib";
use List::Util qw(max);
use Share::DirUtil qw(get_dirs);
use Share::Fahda qw(get_max_dir_number get_xtc_file get_prc_from_clone_path);

my $Clean_Artifacts = 0;
GetOptions(
    "clean-artifacts" => sub { $Clean_Artifacts = 1; },
    "help|h" => sub { print STDOUT HelpMessage(0); }
);

my $Project_Dir      = $ARGV[0] or die "[FATAL]  A PROJ* dir must be specified\n";
my $Ndx_File         = $ARGV[1] or die "[FATAL]  An index file (.ndx) must be specified\n";
my $Native_Structure = $ARGV[2] or die "[FATAL]  A starting structure file (.gro) must be specified\n";
my $Output_Logfile   = $ARGV[3] or die "[FATAL]  An output logfile (.log) must be specified\n";

my $NULL_VALUE_TEXT = "<NULL>";

my $Project_Number   = get_project_number($Project_Dir);
my $Project_Dir_Root = getcwd();
my $Project_Path     = "$Project_Dir_Root/$Project_Dir";

calculate_rmsd_rg($Project_Path);
print STDOUT "Done!\n";

sub calculate_rmsd_rg {
    my ($project_path) = @_;
    chdir $project_path;

    my @run_dirs = get_dirs($project_path, '^RUN\d+$');
    if (scalar(@run_dirs) == 0) {
        print STDOUT "[WARN]  No RUN* dirs found\n";
        exit(0);
    }

    my $max_run_number = get_max_dir_number(@run_dirs);
    for (my $run_number = 0 ; $run_number <= $max_run_number ; $run_number++) {
        my $run_path = "$project_path/RUN$run_number";
        if (not -d $run_path) { next; }
        chdir $run_path;
        print STDOUT "[INFO]  Working on $run_path\n";

        my @clone_dirs = get_dirs($run_path, '^CLONE\d+$');
        if (scalar(@clone_dirs) == 0) {
            print STDOUT "[WARN]  No CLONE* dirs found\n";
            next;
        }

        my $max_clone_number = get_max_dir_number(@clone_dirs);
        for (my $clone_number = 0 ; $clone_number <= $max_clone_number ; $clone_number++) {
            my $clone_path = "$run_path/CLONE$clone_number";
            if (not -d $clone_path) { next; }
            chdir $clone_path;
            print STDOUT "[INFO]  Working on $clone_path\n";

            my $rmsd_xvg = generate_xvg("g_rms", $clone_path);
            my $rmsd_xvg_values = parse_xvg("$clone_path/$rmsd_xvg");

            my $rg_xvg = generate_xvg("g_gyrate", $clone_path);
            my $rg_xvg_values = parse_xvg("$clone_path/$rg_xvg");

            print_to_output_logfile("$Project_Dir_Root/$Output_Logfile",
                $run_number, $clone_number, $rmsd_xvg_values, $rg_xvg_values);

            if ($Clean_Artifacts) {
                `rm -f $rmsd_xvg 2> /dev/null`;
                `rm -f $rg_xvg 2> /dev/null`;
            }

            chdir "..";
        }
        chdir "..";
    }
}

sub get_project_number {
    my ($project_dir) = @_;

    $project_dir =~ s/\/$//;      # remove trailing slash
    $project_dir =~ s/^PROJ//;    # remove PROJ
    return $project_dir;
}

sub generate_xvg {
    my ($g_tools_cmd, $clone_path) = @_;

    my $output_suffix = $g_tools_cmd;
    $output_suffix =~ s/^g_//;

    my ($project_number, $run_number, $clone_number) = get_prc_from_clone_path($clone_path);
    my $xvg_file = "P${project_number}_R${run_number}_C${clone_number}_${output_suffix}.xvg";
    if (-e $xvg_file) { return $xvg_file; }

    my $xtc_file = get_xtc_file($clone_path);
    if (not defined $xtc_file) { return; }
    my $gmx_cmd = "echo 1 1 | $g_tools_cmd -s $Native_Structure -f $xtc_file -n $Ndx_File -o $xvg_file 2> /dev/null";
    `$gmx_cmd`;

    return $xvg_file;
}

sub parse_xvg {
    my ($xvg) = @_;
    if (not -e $xvg) { return; }

    my %xvg_values = ();    # time_in_ps => rmsd_in_angstrom
    open(my $XVG, '<', $xvg);
    while (my $line = <$XVG>) {
        if ($line =~ m/^#/ or $line =~ m/^@/) { next; }    # ignores comments
        chomp(my @values = split(/\b\s+\b/, $line));
        if (scalar(@values) < 2) { next; }
        my $time_in_ps = int($values[0]);
        $xvg_values{"$time_in_ps"} = $values[1] * 10;      # convert nm to angstrom
    }
    close($XVG);

    return \%xvg_values;
}

sub print_to_output_logfile {
    my ($output_logfile, $run_number, $clone_number, $rmsd_xvg_values, $rg_xvg_values) = @_;

    my $rmsd_xvg_frame_count = scalar(keys %$rmsd_xvg_values);
    my $rg_xvg_frame_count   = scalar(keys %$rg_xvg_values);
    if ($rmsd_xvg_frame_count != $rg_xvg_frame_count) {
        print STDOUT "[WARN]  There's a difference in frame counts between rms.xvg ($rmsd_xvg_frame_count frames) "
          . "and gyrate.xvg ($rg_xvg_frame_count frames); any missing value will be shown as $NULL_VALUE_TEXT\n";
    }

    open(my $OUTPUT, '>>', $output_logfile) or die "[FATAL]  $output_logfile: $!\n";

    my $max_frame = max($rmsd_xvg_frame_count, $rg_xvg_frame_count);
    for (my $frame = 0 ; $frame < $max_frame ; $frame++) {
        my $time_in_ps = $frame * 100;
        my $rmsd       = (defined $$rmsd_xvg_values{"$time_in_ps"}) ? $$rmsd_xvg_values{"$time_in_ps"} : $NULL_VALUE_TEXT;
        my $rg         = (defined $$rg_xvg_values{"$time_in_ps"}) ? $$rg_xvg_values{"$time_in_ps"} : $NULL_VALUE_TEXT;
        printf $OUTPUT "%4d    %4d    %4d    %6d    %7.3f    %7.3f\n", $Project_Number, $run_number, $clone_number, $time_in_ps,
          $rmsd, $rg;
    }

    close($OUTPUT);
}

=head1 NAME

calc-rmsd-rg.pl - calculates RMSD and Rg values for the F@H data

=head1 SYNOPSIS

calc-rmsd-rg.pl <project_dir> <index.ndx> <topol.gro> <output.log>

=over

=item --clean-artifacts

When specified the generated *.xvg files are removed after the script
finishes.

=back

IMPORTANT:

=over

=item *

F<index.ndx> and F<topol.gro> must have absolute paths.

=item *

call C<usegromacs33> or similar before running this script.

=back

=cut
