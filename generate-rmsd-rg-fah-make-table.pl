#!/usr/bin/perl

# ------------------------------------------------------------------------------------
#
# KHAI NGUYEN
# CSU LONG BEACH 2014
#
# ------------------------------------------------------------------------------------

# This script extract RMSD and Rg values for the F@H data.
# Type `usegromacs???`, where ??? stands for GROMACS version, before running this script

$usage = "perl  script.pl  [project]  [output-file]";
# ------------------------------------------------------------------------------------
# GET ARGUMENTS
	$project = $ARGV[0] or die "$usage\n";
	$output = $ARGV[1] or die "$usage\n";


# ------------------------------------------------------------------------------------
# ?
	$num_runs = 41;
	$num_clones = 200;

	open (OUTPUT, ">$output") or die "Cannot write to output file $output. $!\n";
	for (my $run=0; $run<$num_runs; $run++){
		for (my $clone=0; $clone<$num_clones; $clone++){
			print "Working on PROJ$project/RUN$run/CLONE$clone...\n";

			my $rmsd_output = "P$project"."_R$run"."_C$clone"."_rmsd.xvg";
			my $gyrate_output = "P$project"."_R$run"."_C$clone"."_gyrate.xvg";

			my %frames_rmsd  = (); # stores rmsd values for each frame
			my %frames_exist = (); # check if a frame has already been read

# ------------------------------------------------------------------------------------
# SAVE RMSD VALUES INTO LOCAL HASH			
			if (-e $rmsd_output) {open RMSD, "<$rmsd_output";}
			while (my $line = <RMSD>){
				if (($line =~ m/#/) or ($line =~ m/@/)){ next; } # ignores comments
				chomp($line);
				foreach ($line) { s/^\s+//; s/\s+$//; s/\s+/ /g;}
				my @items = split(/ /,$line);
				
				my $frame = int($items[0]); # only get the integer part of each time stamp
				$frames_rmsd{$frame} = $items[1]*10; # convert rmsd in nm to Angstrom
				$frames_exist{"$project:$run:$clone:$frame"} = 0; # initialize the hash
			} # END OF reading rmsd file
			close RMSD;

# ------------------------------------------------------------------------------------
# READ RG VALUES AND PRINT RMSD & RG VALUES TO OUTPUT			
			if (-e $gyrate_output) {open RG, "<$gyrate_output"; }
			while (my $line = <RG>){
				if (($line =~ m/#/) or ($line =~ m/@/)){ next; } # ignores comments
				chomp($line);
				foreach ($line) { s/^\s+//; s/\s+$//; s/\s+/ /g;}
				my @items = split(/ /,$line);
				
				if ($frames_exits{"$project:$run:$clone:$items[0]"}==1) { 
					print "$project:$run:$clone:$items[0] exists.\n"; 
					next; 
				}else{
					$frames_exits{"$project:$run:$clone:$items[0]"} = 1;
					$items[1] *= 10; #converts nm to Angstrom for Rg
					print OUTPUT "$project\t $run\t $clone\t $items[0]\t";
					printf OUTPUT "%.3f\t%.3f\n", $frames_rmsd{$items[0]}, $items[1];
				}
			} # END OF reading gyrate file
			close RG;
		} # END OF LOOP THROUGH CLONE* directories
	} # END OF LOOP THROUGH RUN* directories

	close OUTPUT;
	print "Done!\n";