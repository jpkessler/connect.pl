#!/usr/bin/perl -W

use strict;
use warnings;
use Time::HiRes qw(time);
use IO::Pipe;
use IO::Socket qw(SOCK_STREAM);
use Getopt::Long 2.25 qw(:config no_ignore_case bundling);
use vars qw( %RESULTS @CHECKS %kinder $kind $check $wait %CHILDPROCS );
$| = 1;

my $VERBOSE	= 0;
my $TIMEOUT	= 2;
my $ROUNDTRIP	= 3;
my $BATCHMODE	= 0;
my $COUNTER	= 0;
my $SYSLOG	= 0;
my $SELF	= $0; $SELF = $1 if $SELF =~ m@/([^/]+)$@;
our $PIPE	= IO::Pipe->new();

%CHILDPROCS = (

	## CHILD CODE TCP
	"tcp" => sub {
		my ($ADDR, $PORT) = @_;
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
		                printf $PIPE "$ADDR:$PORT;ok;%s;%.1fms;success\n", datum(), ((time() - $t) * 1000);
       		 	        close($socket);
		        } else {
				my $err = $@;
				$err =~ s/^IO::Socket::INET:\s+//;
				$err =~ s/^connect:\s+//;
		                printf $PIPE "$ADDR:$PORT;FAIL;%s;%.1fms;failure [$err]\n", datum(), ((time() - $t) * 1000);
		        };
			my $stime = time();
       			select(undef, undef, undef, ($rtime - $stime)) if $rtime > $stime;
		};
	},


	# CHILD CODE ICMP
	"icmp" => sub {
		my ($ADDR, $PORT) = @_;
		while(1) {
       		 	my $t = time();
			my $rtime = $t + $ROUNDTRIP;
			if ( (system("ping -q -n -c1 -W $TIMEOUT $ADDR >/dev/null 2>&1") == 0) ) {
		                printf $PIPE "$ADDR:$PORT;ok;%s;%.1fms;success\n", datum(), ((time() - $t) * 1000);
			} else {
		                printf $PIPE "$ADDR:$PORT;FAIL;%s;%.1fms;failure\n", datum(), ((time() - $t) * 1000);
			};
			my $stime = time();
       			select(undef, undef, undef, ($rtime - $stime)) if $rtime > $stime;
		};
	},
	"ping" => sub { &{$CHILDPROCS{"icmp"}}(@_); },

	# CHILD CODE DNS
	"dns" => sub {
		my ($ADDR, $PORT) = @_;
		my ($REM, $QUERY, $TYPE) = split /=/, $PORT;
		$TYPE ||= 'A';
		while(1) {
        		my $t = time();
			my $rtime = $t + $ROUNDTRIP;
			if ( (system("host -W $TIMEOUT -t $TYPE $QUERY $ADDR >/dev/null 2>&1") == 0) ) {
		                printf $PIPE "$ADDR:$PORT;ok;%s;%.1fms;success\n", datum(), ((time() - $t) * 1000);
			} else {
		                printf $PIPE "$ADDR:$PORT;FAIL;%s;%.1fms;failure\n", datum(), ((time() - $t) * 1000);
			};
			my $stime = time();
       			select(undef, undef, undef, ($rtime - $stime)) if $rtime > $stime;
        	};
	},

	# CHILD CODE HTTP and FTP
	"web" => sub {
		my ($ADDR, $PORT) = @_; $PORT = lc($PORT);
		my ($tproto, $tport) = split /=/, $PORT;
		$tport = ($tport =~ /^[0-9]+$/) ? ':'.$tport : '';
		while(1) {
        		my $t = time();
			my $rtime = $t + $ROUNDTRIP;
			if ( (system("wget -q -t 1 -T $TIMEOUT --no-check-certificate -O /dev/null ".$tproto."://".$ADDR.$tport." >/dev/null 2>&1") == 0) ) {
		                printf $PIPE "$ADDR:$PORT;ok;%s;%.1fms;success\n", datum(), ((time() - $t) * 1000);
			} else {
		                printf $PIPE "$ADDR:$PORT;FAIL;%s;%.1fms;failure\n", datum(), ((time() - $t) * 1000);
			};
			my $stime = time();
       			select(undef, undef, undef, ($rtime - $stime)) if $rtime > $stime;
        	};
	},

	# CHILD CODE SMTP
	"smtp" => sub {
		my ($ADDR, $PORT) = @_;
		my $tport = ($PORT =~ /=([0-9]+)$/) ? $1 : '25';
		while(1) {
       		 	my $t = time();
			my $rtime = $t + $ROUNDTRIP;
		        if ( my $socket = IO::Socket::INET->new(
       		         	PeerAddr        => $ADDR,
       		 	        PeerPort        => $tport,
		                Proto           => 'tcp',
       		         	Timeout         => $TIMEOUT,
       		 	        Type            => SOCK_STREAM
		        ) ) {
				my $res = ''; $res = <$socket>; $res =~ s/[\r\n\s]+$//g;
		                print $socket "HELO test.local\r\n";
				$res = ''; $res = <$socket>; $res =~ s/[\r\n\s]+$//g;
				if ( $res =~ /^2[0-9][0-9]\s/ ) {
					printf $PIPE "$ADDR:$PORT;ok;%s;%.1fms;success [$res]\n", datum(), ((time() - $t) * 1000);
				} else {
					printf $PIPE "$ADDR:$PORT;FAIL;%s;%.1fms;failure [$res]\n", datum(), ((time() - $t) * 1000);
				};
       		 	        close($socket);
		        } else {
				my $err = $@;
				$err =~ s/^IO::Socket::INET:\s+//;
				$err =~ s/^connect:\s+//;
		                printf $PIPE "$ADDR:$PORT;FAIL;%s;%.1fms;failure [$err]\n", datum(), ((time() - $t) * 1000);
		        };
			my $stime = time();
       			select(undef, undef, undef, ($rtime - $stime)) if $rtime > $stime;
		};
	},
);


GetOptions (
	'verbose|v'		=> \$VERBOSE,
	'timeout|t=i'		=> \$TIMEOUT,
	'roundtrip|rtt|r=i'	=> \$ROUNDTRIP,
	'batchmode|batch|b'	=> \$BATCHMODE,
	'counter|count|c=i'	=> \$COUNTER,
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
	my %count = ();
	my $loop  = ($COUNTER) ? $COUNTER + 1 : 1;
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
			$count{$state}++;
			$RESULTS{$conn}{$state}++;
			$RESULTS{$conn}{'state'} = $state;
			$RESULTS{$conn}{'time'} = $time;
			$RESULTS{$conn}{'date'} = $date;
			$RESULTS{$conn}{'error'} = $err;
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
				($RESULTS{$cn}{'error'} || 'waiting');
		};
		push @OUTPUT, ( sprintf "\n Overall:\n%6d fail\n%6d good\n", scalar $count{'FAIL'}, scalar $count{'ok'} );
		if ( $SYSLOG ) {
			open(SLOG, "| logger -p user.info -t $SELF") or die "\nCan not open 'logger': $! - $@\n\n";
			map { print SLOG $_ } @OUTPUT;
			close(SLOG);
		};
		@OUTPUT = ("\n", @OUTPUT);
		unless ( $BATCHMODE ) {
			push @OUTPUT, "\n CTRL+C to stop...\n";
			system("clear");
		};
		map { print } @OUTPUT;
		$loop-- if $COUNTER;
                # sleep a while to reduce cpu usage
                select(undef, undef, undef, $ROUNDTRIP) unless ($loop < 0);
        } until ($wait == -1 or scalar keys %kinder <= 0 or $loop < 0);
	myexit(1);
};


## CHILD CODE SELECTOR
sub child_process {
	$PIPE->writer();
	my ($ADDR, $PORT) = split /:/, $check;
	my $tprobe = ($PORT =~ /^([a-z]+)\b/) ? $1 : "tcp";
	$tprobe = "tcp" unless defined $CHILDPROCS{$tprobe};
	&{$CHILDPROCS{$tprobe}}($ADDR, $PORT);
};


sub datum {
	my @d = `date +%H:%M:%S`;
	chomp(@d);
	return $d[0];
};

sub myexit {
	my $hide = shift;
	print "\nCaught exit signal...\n" unless $hide;
	printf "\n%7s %7s   %s\n", "GOOD", "FAIL", "CONNECTION";
	foreach my $conn (@OCHECKS) {
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
  -c, --count		stop after <i> executions

EOU
	exit(1);
};

