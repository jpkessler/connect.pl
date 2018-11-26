#!/usr/bin/perl -W

use strict;
use warnings;
use Time::HiRes qw(time);
use IO::Pipe;
use IO::Socket qw(SOCK_STREAM);
use Getopt::Long 2.25 qw(:config no_ignore_case bundling);
use vars qw( %RESULTS @CHECKS %kinder $kind $check $wait );
$| = 1;

my $VERBOSE	= 0;
my $TIMEOUT	= 2;
my $ROUNDTRIP	= 3;
my $BATCHMODE	= 0;
my $SYSLOG	= 0;
my $SELF	= $0; $SELF = $1 if $SELF =~ m@/([^/]+)$@;
our $PIPE	= IO::Pipe->new();

GetOptions (
	'verbose|v'		=> \$VERBOSE,
	'timeout|t=i'		=> \$TIMEOUT,
	'roundtrip|rtt|r=i'	=> \$ROUNDTRIP,
	'batchmode|batch|b'	=> \$BATCHMODE,
	'syslog|l'		=> \$SYSLOG,
) or Usage("Unknown argument!");
Usage("No connection arguments!") unless @ARGV;
map { (/:/) ? push @CHECKS, $_ : print STDERR "Ignoring invalid argument '$_'\n" } @ARGV;
my @OCHECKS = @CHECKS;

FORK: while ($check = shift @CHECKS) {
        $kind = fork();
        last FORK unless $kind;
        $kinder{$kind} = 1;
};

## WHO AM I?
($kind) ? parent_process() : child_process() ;
exit(0);


## PARENT CODE
sub parent_process {
	$PIPE->reader();
	$PIPE->blocking(0);
	$SIG{INT}=\&myexit;
	$SIG{TERM}=\&myexit;
        use POSIX ":sys_wait_h";
        # wait until children have finished
        PARENT: do {
                # check children
                CHILD: foreach (keys %kinder) {
                        $wait = waitpid($_,&WNOHANG);
                        last CHILD unless ($wait == -1);
                        delete $kinder{$_};
                };
		while(<$PIPE>) {
			chomp;
			my($conn,$state,$date,$time,$err) = split /;/;
			$RESULTS{$conn}{$state}++;
			$RESULTS{$conn}{'state'} = $state;
			$RESULTS{$conn}{'time'} = $time;
			$RESULTS{$conn}{'date'} = $date;
			$RESULTS{$conn}{'error'} = $err;
#	                printf "%s: %s %s connection to %s\n", $state, $date, $time, $conn
#				if $VERBOSE or $state eq 'FAIL';
		};
		my @OUTPUT = ();
		my $connlen = 10;
		map { my $i = length($_); $connlen = $i if $i > $connlen } @OCHECKS;
		my $FMTLONG	= " %5s  %-".$connlen."s  %8s %7s %7s  %-8s  %s\n";
		push @OUTPUT, sprintf "$FMTLONG",
			"PROBE",
			"CONNECTION",
			"RTT",
			"GOOD",
			"FAIL",
			"TIME",
			"STATE";
		push @OUTPUT, sprintf "$FMTLONG",
			"-----",
			"----------",
			"---",
			"----",
			"----",
			"----",
			"-----";
		foreach my $cn (@OCHECKS) {
			push @OUTPUT, sprintf "$FMTLONG",
				($RESULTS{$cn}{'state'} || 'INIT'),
				$cn,
				($RESULTS{$cn}{'time'} || '0.0'),
				($RESULTS{$cn}{'ok'} || '0'),
				($RESULTS{$cn}{'FAIL'} || '0'),
				($RESULTS{$cn}{'date'} || '-'),
				($RESULTS{$cn}{'error'} || '-');
		};
		if ( $SYSLOG ) {
			open(SLOG, "| logger -p user.info -t $SELF") or die "\nCan not open 'logger': $! - $@\n\n";
			map { print SLOG $_ } @OUTPUT;
			close(SLOG);
		};
		@OUTPUT = ("\n", @OUTPUT);
		push @OUTPUT, "\n CTRL+C to stop...\n" unless $BATCHMODE;
		system("clear") unless $BATCHMODE;
		map { print } @OUTPUT;
                # sleep a while to reduce cpu usage
                select(undef, undef, undef, $ROUNDTRIP);
        } until ($wait == -1 or scalar keys %kinder <= 0);
};

## CHILD CODE
sub child_process {
	$PIPE->writer();
	my ($ADDR, $PORT) = split /:/, $check;
	while(1) {
        	my $t = time();
		my $rtime = $t + $ROUNDTRIP;
	        if ( my $socket = IO::Socket::INET->new(
                	PeerAddr        => $ADDR,
        	        PeerPort        => $PORT,
	                Proto           => 'tcp',
                	Timeout         => $TIMEOUT,
        	        Type            => SOCK_STREAM
	        ) ) {
	                printf $PIPE "$ADDR:$PORT;ok;%s;%.1fms;established\n", datum(), ((time() - $t) * 1000);
        	        close($socket);
	        } else {
			my $err = $@;
			$err =~ s/^IO::Socket::INET:\s+//;
			$err =~ s/^connect:\s+//;
	                printf $PIPE "$ADDR:$PORT;FAIL;%s;%.1fms;$err\n", datum(), ((time() - $t) * 1000);
	        };
		my $stime = time();
       		select(undef, undef, undef, ($rtime - $stime)) if $rtime > $stime;
	};
};

sub datum {
	my @d = `date +%H:%M:%S`;
	chomp(@d);
	return $d[0];
};

sub myexit {
	print "\nCaught exit signal...\n\n";
	printf "%7s %7s   %s\n", "GOOD", "FAIL", "CONNECTION";
	foreach my $conn (sort keys %RESULTS) {
		printf "%7d %7d   %s\n",
			($RESULTS{$conn}{'ok'} || 0),
			($RESULTS{$conn}{'FAIL'} || 0),
			$conn;
	};
	print "\n";
	exit(0);
};

sub Usage {
	my $err = shift;
	print STDERR "\n$err\n\n";
	print STDERR <<EOU;
USAGE:	$SELF [ OPTIONS ] <address:port> [ <address:port> ... ]

  -v, --verbose		show more information
  -l, --syslog		send output to syslog, too
  -t, --timeout=<i>	set TCP timeout to <i> seconds [default=$TIMEOUT]
  -r, --rtt=<i>		wait for <i> seconds between connections [default=$ROUNDTRIP]
  -b, --batchmode	no clear screen, between rounds

EOU
	exit(1);
};

