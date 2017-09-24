#!/usr/bin/perl

# ------------------------------------------------------------------------------------
#
# KHAI NGUYEN
# CSU LONG BEACH 2014
#
# ------------------------------------------------------------------------------------

# This script extract RMSD and Rg values for the F@H data.
# Type `usegromacs???`, where ??? stands for GROMACS version, before running this script

$usage = "perl  script.pl  [project]  [ndx file]  [starting structure]
NOTE: ndx and starting structure files must have absolute paths";
# ------------------------------------------------------------------------------------
# GET ARGUMENTS
	$project       = $ARGV[0] or die "$usage\n";
	$ndx           = $ARGV[1] or die "$usage\n";
	$nativeStrture = $ARGV[2] or die "$usage\n";


# ------------------------------------------------------------------------------------
# ?
	$num_runs = &count_directory("RUN");
	print "Number of runs is $num_runs\n";
	$currentDir = `pwd`; chomp($currentDir);
	mkdir "RMSD-RG";

	for (my $run=0; $run<$num_runs; $run++){
		# go to a run dir and count number of clones
		chdir "RUN$run";
		my $num_clones = &count_directory("CLONE");
		print "RUN$run: $num_clones clones\n";

		for (my $clone=0; $clone<$num_clones; $clone++){
			# go to each clone and run g_rms & g_gyrate
			chdir "CLONE$clone";
			print "Working on PROJ$project/RUN$run/CLONE$clone...\n";

			my $rmsd_output = "P$project"."_R$run"."_C$clone"."_rmsd.xvg";
			my $gyrate_output = "P$project"."_R$run"."_C$clone"."_gyrate.xvg";
			my $xtc = "P$project"."_R$run"."_C$clone".".xtc";
			`echo 1 1 | g_rms -s $nativeStrture -f $xtc -n $ndx -o $rmsd_output`;
			`echo 1 | g_gyrate -s $nativeStrture -f $xtc -n $ndx -o $gyrate_output`;
			
			my $RMSD_dir = "$currentDir"."/RMSD-RG";
			`mv $rmsd_output $RMSD_dir`;
			`mv $gyrate_output $RMSD_dir`;

			chdir ".."; # go out of CLONE* directory
		} # END OF LOOP THROUGH CLONE* directories
		chdir ".."; # go out of RUN* directory
	} # END OF LOOP THROUGH RUN* directories

	#close OUTPUT;

sub count_directory{ # arguments: pattern in directory names
	local($pattern,@num_dir);
	$pattern = $_[0];
	@num_dir = `tree -i -L 1 | grep $pattern`;
	return scalar(@num_dir);
}
