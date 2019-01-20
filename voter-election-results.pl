use strict;
use warnings;
$| = 1;
use File::Basename;
use DBI;
use Data::Dumper;
use Getopt::Long qw(GetOptions);

#use Switch;
use Time::Piece;

=head1 Function
=over
=heax		d2 Overview
	This program will create a master vote-race-by-precinct table
		Inputs:
		a) input election-file is sorted by precinct and contains 
		- a list of precincts followed by 
		    votes-cast, registered-voters, candidate-1-[party], candidate-2-[party], none, total
		b) input race-file is sorted by precinct and contains
		    candidate-1-[party], candidate-2-[party], none, total
		
	    Output: 
	        a csv file containing a list of precints followed by 
	        one or more 4-column-groups of race results
	        
	    Process:
	        open election-file for all races. build a table with the pattern 
	        open race file and match to the column-group that contains candidate-1 and candidate-2
	             then look up precinct in election-file and copy relative cells to the row
	     
=cut

#my $electionFile = "election_pattern.csv";
my $electionFile = "2018_washoe_election.csv";

my $raceFile        = "prod/gen_reno_city_attorney.csv";
my $resultsFile     = "election_results.csv";
my $outputFile      = "2018_washoe_election.csv";
my $raceresultsFile = "race_results.csv";

my $fileName    = "";
my $helpReq     = 0;
my $csvHeadings = "";
my @csvHeadings;
my $line1Read = '';

my $electionPtr;
my $electionData;
my @electionData = ();
my $electionName;
my @electionHash = ();
my %electionHash;
my $electionHash;
my $electionHeadings = "";
my @electionHeadings;

my $racePtr;
my @raceHash = ();
my %raceHash;
my @raceHeadings;
my $raceData;
my @raceData;
my $raceName;

my $precinct;

my $rest;
my @date;
my @electionPrecinctData;
my @racePrecinctData;
my $racePrecinctData;

my $electionFileh;
my $resultsFileh;
my $raceFileh;
my $outputFileh;

#
# main program controller
#

# Parse any parameters
GetOptions(
	'electionfile=s' => \$electionFile,
	'racefile=s'     => \$raceFile,
	'resultfile=s'   => \$resultsFile,
	'help!'          => \$helpReq,
) or die "Incorrect usage!\n";
if ($helpReq) {
	print "Come on, it's really not that hard.\n";
}
else {
	print "My electionfile is: $electionFile.\n";
	print "My racefile is: $raceFile.\n";
}
unless ( open( $electionFileh, $electionFile ) ) {
	die "Unable to open electionFile: $electionFile Reason: $!\n";
}

# pick out the heading line and hold it and remove end character
$csvHeadings = <$electionFileh>;
chomp $csvHeadings;
chop $csvHeadings;

# headings in an array to modify
# @electionHeadings will be used to create the files
@electionHeadings = split( /\s*,\s*/, $csvHeadings );

#print $resultsFileh $precinct, join( ',', @electionHeadings ), "\n";
$precinct = '000000';
$electionHash{$precinct} = [@electionHeadings];

# build Election Results table
#
# Read the entire election file and create pattern table
while ( $line1Read = <$electionFileh> ) {
	chomp $line1Read;
	$line1Read =~ s/(?:\G(?!\A)|[^"]*")[^",]*\K(?:,|"(*SKIP)(*FAIL))/ /g;
	( $precinct, $rest ) = split /,\s*/, $line1Read, 2;
	$precinct =~ s/^\s+|\s+$//g;
	@electionPrecinctData = split( ',', $rest );
	foreach (@electionPrecinctData) {
		$_ =~ s/\D+//g;
	}

	# Create hash entry for each precinct
	$electionHash{$precinct} = [@electionPrecinctData];
}

# completed initilization

close($electionFileh);

#
# open the Race File and create hash of precincts
#
unless ( open( $raceFileh, $raceFile ) ) {
	die "Unable to open raceFile: $raceFile Reason: $!\n";
}
$csvHeadings = <$raceFileh>;
chomp $csvHeadings;
chop $csvHeadings;
@raceHeadings = split( /\s*,\s*/, $csvHeadings );
print $raceFileh $precinct, ',', join( ',', @raceHeadings ), "\n";
$precinct = '000000';
$raceHash{$precinct} = \@raceHeadings;

#
# Read the each RACE entry and process
while ( $line1Read = <$raceFileh> ) {
	chomp $line1Read;
	$line1Read =~ s/(?:\G(?!\A)|[^"]*")[^",]*\K(?:,|"(*SKIP)(*FAIL))/ /g;
	( $precinct, $rest ) = split /,\s*/, $line1Read, 2;
	$precinct =~ s/^\s+|\s+$//g;
	@racePrecinctData = split( ',', $rest );
	foreach (@racePrecinctData) {
		$_ =~ s/\D+//g;
	}

	# Create hash entry for each precinct
	$raceHash{$precinct} = [@racePrecinctData];
}
#
close($raceFileh);

#
# run the raceHash for the precincts
#  - get the race name from raceHash
#  - copy data to corresponding columns in electionHash
#
# set the offset to first name cell
$racePtr = 3;

# pick up the title row of electionHash and raceHash
@electionData = @{ $electionHash{"000000"} };
$electionName = $electionData[$racePtr];
@raceData     = @{ $raceHash{"000000"} };

# identifiy the race to look for in the electionHash
$raceName    = $raceData[3];
$electionPtr = -1;             #set pointer first iteration

# Find the start of race in electionHash
do {
	if ( $electionPtr == -1 ) {
		$electionPtr = 3;      #bump offset in electionHash
	}
	else {
		$electionPtr = $electionPtr + 5;    #bump offset in electionHash
	}
	$electionName = $electionData[$electionPtr];
} until ( $electionName eq $raceName || "LastName" eq $raceName );

# electionPtr points the offset of a race in electionHash
# Now iterate thrugh precincts of raceHash for the candidate
#    first(non-blank), then for the 4 fields
#    move data over from the cell in raceHash to electionHash

#  key   + 0    + 1   + 2        + 3     + 4     + 5    + 6   |
# | Prec | Cast | Reg | racename | cand1 | cand2 | none | total|
foreach my $precinct ( sort keys %raceHash ) {
	@raceData = @{ $raceHash{$precinct} };
	next if ( $precinct eq "000000" );
	if ( exists( $electionHash{$precinct} ) ) {

		# we have the raceHash row now update the electionHash row
		@electionData                     = @{ $electionHash{$precinct} };
		$electionData[ $electionPtr + 0 ] = $raceData[3];
		$electionData[ $electionPtr + 1 ] = $raceData[4];
		$electionData[ $electionPtr + 2 ] = $raceData[5];
		$electionData[ $electionPtr + 3 ] = $raceData[6];
		$electionHash{$precinct}          = [@electionData];
		print $precinct, ',', join( ',', @electionData ), "\n";
	}
}

close($raceFileh);

#
# writeout the completed election hash
#
unless ( open( $outputFileh, ">$outputFile" ) ) {
	die "Unable to open outputFileh: $outputFileh Reason: $!\n";
}

# header
print $outputFileh join( ',', @electionHeadings ), "\n";

foreach my $precinct ( sort keys %electionHash ) {
	if ( $precinct ne "000000" ) {
		@electionData = @{ $electionHash{$precinct} };
		print $outputFileh $precinct, ',', join( ',', @electionData ), "\n";
	}
}

#
# Program complete
#
print " <===> Completed conversion of: $electionFile \n";
print " <===> Output available in file: $outputFile \n";

#print " <===> Total Records Read: $linesRead \n";
#print " <===> Total Records written: $linesWritten \n";
exit;
#

sub percentage {
	my $val = $_;
	return ( sprintf( "%.2f", ( $- * 100 ) ) . "%" . $/ );
}

sub desc_sort {
	$b <=> $a;    # Numeric sort descending
}

sub asc_sort {
	$a <=> $b;    # Numeric sort ascending
}
