#!/usr/bin/perl

use Data::Dumper;

use constant SEGMENT_ROWS => 3;
use constant SEGMENT_COLS => 3;
use constant GRID_SIZE => SEGMENT_ROWS * SEGMENT_COLS;
use constant VALUES => 1..GRID_SIZE;
use constant SLOTS => 0..GRID_SIZE-1;
use constant CHARSET => ' 123456789ABCDEF';

my @chars = split('',CHARSET);
my $board = {
    squares => [],
};

# read in the board
while (<STDIN>) {
    chomp;
    tr/a-z/A-Z/;
    my @line = map { hex($_) } split('',$_);
    push @{$board->{squares}}, \@line;
}
# validate the size of the board if you like...
showboard($board);

# Elimination round first: run two passes until we're finished or stuck
# - pass 1: determine possibilities for each empty square
# - pass 2: determine which possibilities are unique to a square
my $pass = 0;
my $filled;
my $unsolved;
do {
    $unsolved = 0;
    $filled = 0;

    # Pass 1
    $board->{poss} = [];
    foreach my $row (SLOTS) {
	foreach my $col (SLOTS) {
	    if ($board->{squares}->[$row][$col]) {
		$board->{poss}->[$row][$col] = [ $board->{squares}->[$row][$col] ];
	    } else {
		$board->{poss}->[$row][$col] = possibilities($board, $row, $col);
		# print "Possibilities for [$row][$col]: [" . join("][",map { @chars[$_] } @{$board->{poss}->[$row][$col]}) . "]\n";
		if (@{$board->{poss}->[$row][$col]} == 1) {
		    my ($val) = @{$board->{poss}->[$row][$col]};
		    print "[$row][$col] can only be [$val]\n";
		    $board->{squares}->[$row][$col] = $val;
		    $filled++;
		} else {
		    $unsolved++;
		}
	    }
	}
    }

    # Pass 2
    foreach my $row (SLOTS) {
	foreach my $col (SLOTS) {
	    next if @{$board->{poss}->[$row][$col]} == 1;
	    foreach my $val (@{$board->{poss}->[$row][$col]}) {
		my $uniq = { row => 1, col => 1, seg => 1 };
		foreach my $i (SLOTS) {
		    if ($uniq->{row} && $col != $i) {
			$uniq->{row} &&=
			    !grep { $_ == $val } @{$board->{poss}->[$row][$i]};
		    }
		    if ($uniq->{col} && $row != $i) {
			$uniq->{col} &&=
			    !grep { $_ == $val } @{$board->{poss}->[$i][$col]};
		    }
		}
		my $h1 = int($row/SEGMENT_ROWS)*SEGMENT_ROWS;
		my $h2 = $h1+SEGMENT_ROWS-1;
		my $v1 = int($col/SEGMENT_COLS)*SEGMENT_COLS;
		my $v2 = $v1+SEGMENT_COLS-1;
		# print "Checking uniq for [$row][$col] in seg [$h1,v1]-[$h2,v2]\n";
		foreach my $h ($h1..$h2) {
		    foreach my $v ($v1..$v2) {
			next unless $uniq->{seg};
			next if $row == $h && $col == $v;
			$uniq->{seg} &&=
			    !grep { $_ == $val } @{$board->{poss}->[$h][$v]};
		    }
		}
		my @uniq_locs = grep { $uniq->{$_} } keys %$uniq;
		if (@uniq_locs) {
		    print "[$row][$col] is the only location for $chars[$val] in this [" . join("][",@uniq_locs) . "]\n";
		    $board->{poss}->[$row][$col] = [ $val ];
		    $board->{squares}->[$row][$col] = $val;
		    $filled++;
		    $unsolved--;
		    last;
		}
	    }
	}
    }

    $pass++ if $filled;
    print "Filled $filled squares on pass $pass ($unsolved unsolved squares remaining)\n";
    showboard($board) if $filled;
} while ($unsolved && $filled);

# If the elimination round didn't solve the puzzle, use lookahead
if ($unsolved) {
    print "Looks like we got stuck after $pass passes, using lookahead.\n";

    # make a list of unsolved squares and possibilities
    my @nodes;
    foreach my $row (SLOTS) {
	foreach my $col (SLOTS) {
	    next if @{$board->{poss}->[$row][$col]} == 1;
	    my $node = {
		row => $row,
		col => $col,
		poss => undef,
		try => undef,
	    };
	    push @nodes, $node;
	}
    }
    @nodes = sort { @{$board->{poss}->[$a->{row}][$a->{col}]} <=> @{$board->{poss}->[$b->{row}][$b->{col}]} } @nodes;

    # try the possibility graph until the puzzle is solved or stuck
    my $i = 0;
    my $pass = 0;
    while ($i>=0 && $i<=$#nodes) {
	$pass++;

	# if we've already started a possibility set, continue
	my $row = $nodes[$i]->{row};
	my $col = $nodes[$i]->{col};
	my $poss = $nodes[$i]->{poss};
	if (defined($poss)) {
	    my $try = $nodes[$i]->{try};
	    $try++;
	    if ($try < @$poss) {
		# try the next one
		$board->{squares}->[$row][$col] = $poss->[$try];
		$nodes[$i]->{try} = $try;
		$i++;
	    } else {
		# reset this node and move back up the tree
		$board->{squares}->[$row][$col] = 0;
		$nodes[$i]->{poss} = undef;
		$i--;
	    }
	} else {
	    # determine new set of possibilities
	    $poss = possibilities($board, $row, $col);
	    if (@$poss) {
		$nodes[$i]->{poss} = $poss;
		$nodes[$i]->{try} = 0;
		$board->{squares}->[$row][$col] = $poss->[0];
		$i++;
	    } else {
		# failed, reset this node and move back up the tree
		$board->{squares}->[$row][$col] = 0;
		$nodes[$i]->{poss} = undef;
		$i--;
	    }
	}
    }

    if ($i < 0) {
	print "The board seems to be stuck after $pass lookahead passes.\n";
    } else {
	print "The board is solved after $pass lookahead passes.\n";
    }
} else {
    print "Solved the puzzle in $pass passes.\n";
}
showboard($board);

sub possibilities {
    my ($board, $row, $col) = @_;

    my %taken = map { $_ => 0 } VALUES;
    foreach my $i (SLOTS) {
	# Check the values in this row
	$taken{$board->{squares}->[$row][$i]} = 1;

	# Check the values in this column
	$taken{$board->{squares}->[$i][$col]} = 1;
    }

    # Check the values in this segment
    my $h1 = int($row/SEGMENT_ROWS)*SEGMENT_ROWS;
    my $h2 = $h1+SEGMENT_ROWS-1;
    my $v1 = int($col/SEGMENT_COLS)*SEGMENT_COLS;
    my $v2 = $v1+SEGMENT_COLS-1;
    # print "Checking segment [$h1][$v1] - [$h2][$v2] for [$row][$col]\n";
    foreach my $h ($h1..$h2) {
	foreach my $v ($v1..$v2) {
	    $taken{$board->{squares}->[$h][$v]} = 1;
	}
    }

    return [ grep { !$taken{$_} } VALUES ];
}

sub showboard {
    my $board = shift;
    my $row = 1;
    foreach my $line (@{$board->{squares}}) {
	my $col = 1;
	foreach my $square (@$line) {
	    print '[' . $chars[$square] . ']';
	    print ' ' if $col != VALUES && $col % SEGMENT_COLS == 0;
	    $col++;
	}
	print "\n";
	print "\n" if $row != VALUES && $row % SEGMENT_ROWS == 0;
	$row++;
    }
}
