#!/usr/bin/perl

use strict;
use warnings;
use Cwd;
use Getopt::Long qw(HelpMessage :config pass_through);
use List::Util qw(max);

my $Clean_Artifacts = 0;
GetOptions(
    "clean-artifacts" => sub { $Clean_Artifacts = 1; },
    "help|h" => sub { print STDOUT HelpMessage(0); }
);

my $Project_Dir      = $ARGV[0] or die "[FATAL]  A PROJ* dir must be specified\n";
my $Ndx_File         = $ARGV[1] or die "[FATAL]  An index file (.ndx) must be specified\n";
my $Native_Structure = $ARGV[2] or die "[FATAL]  A starting structure file (.gro) must be specified\n";
my $Output_Logfile   = $ARGV[3] or die "[FATAL]  An output logfile (.log) must be specified\n";

my $Project_Number      = get_project_number($Project_Dir);
my $Project_Dir_Root    = getcwd();
my $Path_To_Project_Dir = "$Project_Dir_Root/$Project_Dir";

my $NULL_VALUE_TEXT = "<NULL>";

calculate_rmsd_rg();

sub calculate_rmsd_rg {
    chdir $Path_To_Project_Dir;

    my @run_dirs = get_dirs($Path_To_Project_Dir, "^RUN\\d+\$");
    if (scalar(@run_dirs) == 0) {
        print STDOUT "[WARN]  No RUN* dirs found\n";
        exit(0);
    }

    my $max_run_number = get_max_dir_number(@run_dirs);
    for (my $run_number = 0 ; $run_number <= $max_run_number ; $run_number++) {
        if (not -d "RUN$run_number") { next; }
        chdir "RUN$run_number";
        print STDOUT "[INFO]  Working on $Project_Dir/RUN$run_number\n";

        my @clone_dirs = get_dirs("$Path_To_Project_Dir/RUN$run_number", "^CLONE\\d+\$");
        if (scalar(@clone_dirs) == 0) {
            print STDOUT "[WARN]  No CLONE* dirs found\n";
            next;
        }

        my $max_clone_number = get_max_dir_number(@clone_dirs);
        for (my $clone_number = 0 ; $clone_number <= $max_clone_number ; $clone_number++) {
            if (not -d "CLONE$clone_number") { next; }
            chdir "CLONE$clone_number";
            print STDOUT "[INFO]  Working on $Project_Dir/RUN$run_number/CLONE$clone_number\n";

            my $rmsd_xvg = generate_xvg("g_rms", $Project_Number, $run_number, $clone_number);
            my $rmsd_xvg_values = parse_xvg($rmsd_xvg);

            my $rg_xvg = generate_xvg("g_gyrate", $Project_Number, $run_number, $clone_number);
            my $rg_xvg_values = parse_xvg($rg_xvg);

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

sub get_dirs {
    my ($root, $match_pattern) = @_;
    if (not -d $root) { return; }
    if ($root !~ m/\/$/) { $root .= "/"; }

    opendir(my $ROOT_HANDLE, $root);
    my @dirs = grep { -d "$root$_" && /$match_pattern/ } readdir($ROOT_HANDLE);
    closedir($ROOT_HANDLE);

    return @dirs;
}

sub get_max_dir_number {
    my (@dirs) = @_;
    my @dir_numbers = ();
    foreach my $dir (@dirs) {
        my $dir_number = $dir;
        $dir_number =~ s/^\D+//;
        push(@dir_numbers, int($dir_number));
    }
    return max(@dir_numbers);
}

sub get_xtc_file {
    my ($cwd, $project_number, $run_number, $clone_number) = @_;

    my $xtc_file = "P${project_number}_R${run_number}_C${clone_number}.xtc";
    if (-e $xtc_file) { return $xtc_file; }

    print STDOUT "[WARN]  $xtc_file not found; trying to find another one\n";

    opendir(my $CWD, $cwd);
    my @xtc_files = grep { /\.xtc$/ } readdir($CWD);
    closedir($CWD);

    if (scalar(@xtc_files) == 0) {
        print STDOUT "[WARN]  No XTC file found\n";
        return;
    }

    if (scalar(@xtc_files) > 1) {
        print STDOUT "[WARN]  More than one XTC file found; ";
        chomp($xtc_file = $xtc_files[0]);
        print STDOUT "using the first one: $xtc_file\n";
        return $xtc_file;
    }

    chomp($xtc_file = $xtc_files[0]);
    print STDOUT "[INFO]  Found $xtc_file\n";
    return $xtc_file;
}

sub generate_xvg {
    my ($g_tools_cmd, $project_number, $run_number, $clone_number) = @_;

    my $output_suffix = $g_tools_cmd;
    $output_suffix =~ s/^g_//;
    my $xvg_file = "P${project_number}_R${run_number}_C${clone_number}_${output_suffix}.xvg";
    if (-e $xvg_file) { return $xvg_file; }

    my $xtc_file =
      get_xtc_file("$Path_To_Project_Dir/RUN$run_number/CLONE$clone_number", $project_number, $run_number, $clone_number);

    my $gmx_cmd = "echo 1 1 | $g_tools_cmd -s $Native_Structure -f $xtc_file -n $Ndx_File -o $xvg_file 2> /dev/null";
    print STDOUT "[INFO]  Executing `$gmx_cmd`\n";
    `$gmx_cmd`;

    return $xvg_file;
}

sub parse_xvg {
    my ($xvg) = @_;

    if (not -e $xvg) {

        print STDOUT "[WARN]  $xvg does not exist\n";
        return;
    }

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

fah-rmsd-rg-calc.pl - calculates RMSD and Rg values for the F@H data

=head1 SYNOPSIS

fah-rmsd-rg-calc.pl <project_dir> <index.ndx> <topol.gro> <output.log>

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
