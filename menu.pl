#!/usr/bin/perl
# $Id: menu.pl,v 1.2 2016/03/08 23:23:11 gongcunjust Exp $
use strict;
use Fcntl;
use Fcntl ":flock";
use POSIX qw(:signal_h);
use POSIX qw(:sys_wait_h);
use POSIX qw(:unistd_h);
use Term::ANSIColor ":constants";
use IO::Handle;
use sigtrap qw(die untrapped normal-signals
		stack-trace any error-signals);

use Class::Struct;
use Errno qw(EINTR);
use File::Basename;

my $mainmenu = defined($ARGV[0]) ? $ARGV[0] : "main.men";

# trick to solve the hacmp passwd problem #
if ($ARGV[0] eq "-c") {
	shift @ARGV;
	system "@ARGV" || die $!;
	exit;
}

my $offset = 3;
my $col_offset = 30;
my $COLS = `tput cols`;
my $ROWS = `tput lines`;
my $menu_bottom = 21;
my $FILE;
my @menu;
my $i;
my $on;
my $up = "\033[A";
my $down = "\033[B";
my $left = "\033[D";
my $right = "\033[C";
my $enter = "\n";
my %title;
my $curr_title;
my @previous;
my ($selected, $save_selected, $isselected) = (-1, -1, 0);
my @path;
my $pid;
my $SETALIAS = "./setAlias.ksh";
my $BUFSIZ = 1024;
chomp(my $save = `stty -g`);

$ENV{'TERM'} = 'vt100';
$SIG{'INT'} = 'IGNORE';
$SIG{'QUIT'} = 'IGNORE'; 
$SIG{'ALRM'} = sub { print STDERR "\nProcess $$ exiting...\n"; exit 0};


# remove the script
# unlink $0 or warn "cannot unlink: $!";

# change the working directory
chdir dirname($0) or die "cannot change cwd: $!";

# check the process status #
sysopen GLOBAL, "/dev/zero", O_RDWR || die $!;
my $pack_fmt = 'sslli';
my $ret_info = pack $pack_fmt, F_WRLCK, SEEK_SET, 0, 0, 0 or die $!;
my $flock_info = pack $pack_fmt, F_RDLCK, SEEK_SET, 0, 0, 0 or die $!;

# get lock process-id #
if (fcntl(GLOBAL, F_GETLK, $ret_info)) {
	my $pid = (unpack $pack_fmt, $ret_info)[3];
	if ($pid) {
		printf "the process %d is running, continue(y)/exit(n):", $pid;
		while (chomp(my $c = <STDIN>)) {
			if ($c eq 'y' || $c eq 'Y') {
				last;
			}
			if ($c eq 'n' || $c eq 'N') { 
				exit(1);
			}
			printf "enter:";
		}
	}
} else {
	die "fcntl F_GETLK error $!";
}

# start; shared-lock the global file #
fcntl(GLOBAL, F_SETLK, $flock_info) || die $!;

my $lockfile = "/tmp/$$.lock";
open INPUT,  ">>", "input.log"; 
open OUTPUT, ">>", "output.log";
open LOCKFILE, ">", $lockfile || die $!;
open TTY, "<", "/dev/tty";

chmod 0666, "input.log";
chmod 0666, "output.log";

chomp(my $bottom = `tput lines`);
system "tput civis"; 

sub except_handler { 
	if (defined $@ and length $@) {
		chomp($@);
		my $buf = sprintf("\n%s; Press any key to return...", $@)
			|| die $!;
		my $n = length($buf);
		print STDERR REVERSE $buf, RESET || die $!;
		syswrite(OUTPUT, $buf, $n) == $n || die $!; 
		&getchar;
	} 
}

sub lock {
	flock(LOCKFILE, LOCK_EX);
}

sub unlock {
	flock(LOCKFILE, LOCK_UN);
}

sub dis_time { 
	chomp(my $gettime=`date +%Y-%m-%d' '%T`);
	my $axis = $COLS - length($gettime);
	system "tput cup 0 $axis";
	print $gettime;
}


sub getchar {
	my $c;
	chomp(my $save = `stty -g`);

	system "stty -echo"; 
	system "stty -icanon"; 
	system "stty", 'eof', "\1"; # MIN == 1 #
	system "stty", 'eol',  "\0"; # TIME == 0 # 
	while (sysread(TTY, $c, 3) < 0) {
		die $! if ($! != EINTR);
	}
	system "stty $save"; 
	return $c;
}

sub showmenu {
	system "(stty sane; stty -echo)";
	my $start = $_[0];
	my ($row, $col, $i);
	chomp(my $hostname = `hostname`);
	system "(tput cup 0 0; tput ed)";
	print BOLD WHITE ON_BLUE; 
	print $hostname;
	print RESET;
	system "tput cup 0 15";
	print BOLD YELLOW;
	printf "%-30s", $curr_title;
	print RESET;
	for ($i = 0; $i <= $#menu; $i++) { 
		$row = $menu[$i] -> row;
		$col = $menu[$i] -> col;
		system "tput cup $row $col";
		print $menu[$i] -> desc;
	}

	$row += 2;
	$menu_bottom = $row;
	system "tput cup $row 0";
	print BOLD WHITE "Enter your choice: ", RESET;
	&print_choice($row, 20, $menu[$start]->item);
	if ($on != 0 && $isselected != 0) {
		$row += 2;
		system "tput cup $row 0";
		print BOLD WHITE;
		printf "%-19s", "Previous choice: ";
		print RESET; 
		$selected = $save_selected >= 0 ? $save_selected : $start;
		printf "(%s)", $menu[$selected]->item;
		$save_selected = -1;
	}
	$on = 1;

	if ($menu_bottom + 2 > $ROWS - 1 || $COLS < 80) {
		system "(tput cup 0 0; tput el)";
		print RED "window too small", RESET;
	}

	&mvprint_rev($menu[$start]->row, $menu[$start]->col, $start);
}

my %menu_map;
struct (Menu_cont => {
	item => '$',
	row => '$',
	col => '$',
	desc => '$',
	cmd => '$'
});
my %menu_mtime;

sub readmenu {
	my $row = 0;
	my $col = 0;
	my $savearg = $_[0];
	my @tmp = split(/\//, $_[0]);
	my $FILE = $tmp[-1];
	my $mtime = (stat($FILE))[9];

	goto ASSIGN_MENU if (exists $menu_map{$FILE} && exists $menu_mtime{$FILE} && $menu_mtime{$FILE} == $mtime);

	if (exists $menu_map{$FILE}) {
		delete $menu_map{$FILE};
	}

	$menu_mtime{$FILE} = $mtime;

	if ( ! open READIN, '<', $FILE ) { 
		&quit(1, "can't open file $FILE");
	}

	while (my $line = <READIN>) {
	  chomp($line);
	  if ($row == 0) {
	    $title{$savearg} = $line;
	    $row++;
	  } elsif (length($line) == 0) {
	    $row++;
	  }
	  if ($line =~ /\A[0-9a-zA-Z]\)/) {
	    push @{ $menu_map{$FILE} }, Menu_cont->new(
	      item => substr($line, 0, 1),
	      row => $row++,
	      col => $col,
	      desc => $line
	    );
	  }
	}
	close READIN;

	if ( ! open READIN, '<', $FILE ) {
		&quit(1, "can't open file $FILE");
	}
	while (my $line = <READIN>) {
	  chomp($line);
	  if ($line =~ /\A[0-9a-zA-Z]\@/) {
            my $item = substr($line, 0, 1);
            my $cmd = substr($line, 2);
            for (my $i = 0; $i <= $#{ $menu_map{$FILE} }; $i++) {
              if ($menu_map{$FILE}[$i] -> item eq $item) {
                $menu_map{$FILE}[$i] -> cmd($cmd);
              }
            }
          }
        }
	close READIN;

	$row += $offset;

	push @{ $menu_map{$FILE} }, Menu_cont->new(
	  item => 'b',
	  row => $row,
	  col => $col,
	  desc => "b) Go back one menu",
	  cmd => 'b'
	);

	$col += $col_offset;
	push @{ $menu_map{$FILE} }, Menu_cont->new(
	  item => 'm',
	  row => $row,
	  col => $col,
	  desc => "m) Go to the main menu",
	  cmd => 'm'
	);

	$col += $col_offset;
	push @{ $menu_map{$FILE} }, Menu_cont->new(
	  item => 'x',
	  row => $row,
	  col => $col,
	  desc => "x) Quit",
	  cmd => 'x'
	);

ASSIGN_MENU:
	undef(@menu);
	@menu = @{ $menu_map{$FILE} };
}

sub mvprint_rev {
	my $row = $_[0];
	my $col = $_[1];
	my $idx = $_[2];
	system "tput cup $row $col";
	print REVERSE $menu[$idx]->desc, RESET;
}

sub mvprint {
	my $row = $_[0];
	my $col = $_[1];
	my $idx = $_[2];
	system "tput cup $row $col";
	print $menu[$idx]->desc." "; 
}

sub print_choice {
	my $row = $_[0];
	my $col = $_[1];
	my $cho = $_[2];
	system "(tput cup $row $col; tput el)";
	print BOLD CYAN;
	printf "%s", $cho;
	print RESET;
}

sub quit {
	my $rc = $_[0];
	if (defined($pid)) { 
		# SIGALRM will terminate the child #
		kill 14, $pid; 
	}
	while (waitpid($pid, 0) < 0) {
		last if ($! != EINTR);
	}
	system "clear";
	system "tput cnorm";
	system "stty $save";
	if (defined($_[1])) {
		my $msg = $_[1];
		print "$msg"."\n";
	}
	exit $rc;
}

sub logger {
	my $content = $_[0];
	chomp(my $user = `whoami`);
	chomp(my $tty = `tty`);
	my $pid = $$;
	chomp(my $gettime=`date +%Y-%m-%d' '%T`);
	print INPUT "[".$user."][".$tty."][".$pid."]"."@".$gettime."@".$content."\n";
}


sub dump_exec {
	my $cmd = $_[0];
	my $timestamp;
	my ($buf, $n, $execpid);

	pipe(FH0, FH1) or die $!;

	if (($execpid = fork()) < 0) {
		die "Can't fork process: $!";
	} elsif ($execpid == 0) { # child to execute the system command
		my ($envcmd, $ptycmd) = ("", ""); 
		$ptycmd = "./pty.exp " if -e "./pty.exp" and length(`which expect 2>/dev/null`) > 0;

		##
		## Remove the 'PAUSE', suppose the command don't have brace
		##
		my @fields = split /\;/, $cmd;
		$cmd = "";
		foreach my $i (0..$#fields) {
			next if ($fields[$i] =~ /\bPAUSE\b/);
			$cmd .= "eval $ptycmd $fields[$i]; ";
		}

		my $tmp = $_;
		$_ = $cmd; s/\;\s+$//g; $cmd = "($_) 2>&1";
		$_ = $tmp;

		$envcmd = ". $SETALIAS; " if -e $SETALIAS;
		$cmd = $envcmd . "$cmd";

		chomp(my $gettime=`date +%Y-%m-%d' '%T`);
		$timestamp = sprintf("\n[%s] %s\n", $gettime, $cmd) or die $!;
		$n = length($timestamp);
		syswrite(OUTPUT, $timestamp, $n) == $n || die $!;

		close FH0;
		open(STDOUT, ">&FH1") || die "Can't dup STDOUT to FH1";
		open(STDERR, ">&FH1") || die "Can't dup STDERR to FH1";
		close FH1;
		exec($cmd) || die "exec error: $!";
	}

	# Parent continue...
	close FH1;
	open DUMPLOG, ">", "/tmp/$$.log" || die "Open tmp log file error: $!"; 
	while (($n = sysread(FH0, $buf, $BUFSIZ)) > 0) {
		syswrite(STDOUT, $buf, $n) == $n || die "Write to stdout error: $!";
		syswrite(OUTPUT, $buf, $n) == $n || die "Write to output.log error: $!";
		syswrite(DUMPLOG, $buf, $n) == $n || die "Write to tmp log error: $!"; # dump output for paging
	}
	waitpid($execpid, 0);
	my $rc = $?;

	if ( (my $exit_value = ($rc >> 8)) != 0 ) {
		if (my $exit_signal = ($rc & 127)) {
			print  DUMPLOG "The program is interrupted by signal: $exit_signal\n" || die $!;
		}
		print  DUMPLOG "Warning: the program exit code = $exit_value\n" || die $!;
	}
	close DUMPLOG;

	system "more -dv -pG </tmp/$$.log";
	system "cat /tmp/$$.log >>output.log";

	unlink "/tmp/$$.log";

	return;
}

#
# main call
#

# child process to display time
defined($pid = fork) or die "can't fork: $!\n";
if ($pid == 0) {
	my ($sigset, $oldset);
	my $SIGWINCH = 28;

	$sigset = POSIX::SigSet->new() || die;
	$sigset->emptyset() || die $!;
	$sigset->addset($SIGWINCH) || die $!;
	$oldset = POSIX::SigSet->new() || die;
	

	local $SIG{'WINCH'} = sub { $COLS = `tput cols` };
	while (1) { 
		sigprocmask(SIG_BLOCK, $sigset, $oldset) || die $!;
		&lock;
		&dis_time;
		&unlock;
		system "sleep 1";
		sigprocmask(SIG_SETMASK, $oldset) || die $!;
	}
	exit(0);
}

# longjmp()
$SIG{'WINCH'} = sub {
	$COLS = `tput cols`;
	$ROWS = `tput lines`;
	$save_selected = $selected;
	die "caught SIGWINCH\n";
};

# parent process continue...
$FILE = $mainmenu; 
push @path, $FILE;
$i = 0;
$on = 0;

do { eval { while (1) { # setjmp()
	if (@path == undef) {
		undef(@previous);
		$FILE = $mainmenu; 
		push @path, $FILE;
		$i = 0;
		$on = 0;
		$isselected = 0;
	} else {
		$FILE = $path[-1];
	}
	&readmenu($FILE);
	$curr_title = $title{$FILE};
	&lock;
	&showmenu($i); 
	&unlock;
START: 
	my $key = &getchar;
	my $order = "unknown choice";
	if ($key eq $down || $key eq $right || $key eq $up || $key eq $left || 
		substr($key, 0, 1) =~ /[a-zA-Z0-9]/) 
	{ 
		&lock; 
		&mvprint($menu[$i]->row, $menu[$i]->col, $i);

		if ($key eq $down || $key eq $right) { 
			$i += 1; 
			$i = $i > $#menu ? 0 : $i;
			$order = $menu[$i]->item;
		} elsif ($key eq $up || $key eq $left) {
			$i -= 1;
			$i = $i < 0 ? $#menu : $i;
			$order = $menu[$i]->item;
		} else {
			foreach my $n (0..$#menu) {
				if ($key eq $menu[$n]->item) {
					$i = $n; 
					$order = $key;
					last;
				}
			}
		}

		&print_choice($menu_bottom, 20, $order);

		&mvprint_rev($menu[$i]->row, $menu[$i]->col, $i);

		&unlock;
		goto START;
	} elsif ($key eq $enter) {
		$isselected = 1;
		&lock;
		if ($menu[$i]->cmd eq "x") { 
			&logger("exit");
			&quit(0);
		} elsif ($menu[$i]->cmd eq "m") {
			undef(@path);
			$FILE = $mainmenu;
			&logger("main_menu $FILE");
			$i = 0;
			undef(@previous);
		} elsif ($menu[$i]->cmd eq "b") { 
			pop @path;
			&logger("back_menu $path[-1]");
			$i = pop @previous;
			if ($i == undef) {
				$i = 0;
			}
		} else {
			&logger($menu[$i]->cmd);
			my $command = $menu[$i]->cmd;
			if ( !(defined $command) or length($command) == 0 ) {
				$order = "Can't find the command";
				goto EXCEPTION;
			}
			if ($command =~ /\Achange_menu/) { 
				$on = 0;
				$isselected = 0;
				push @previous, $i;
				my @fields = split /\s+/, $command;
				push @path, $fields[1];
				$i = 0;
			} else { 
				local $SIG{'WINCH'} = 'IGNORE';
				system "clear";
				system "stty $save";
				system "tput cnorm";
				if ($menu[$i]->cmd =~ /\bPAUSE\b/) {
					&dump_exec($menu[$i]->cmd);
				} else { 
					my $cmd = $menu[$i]->cmd;
					$cmd = ". $SETALIAS; eval " . $cmd if -e $SETALIAS;
					system($cmd);
				}
				system "stty $save";
				system "tput civis";
			}
		} 
		&unlock;
	} else {
EXCEPTION:
		&lock;
		&print_choice($menu_bottom, 20, $order);
		&unlock;
		goto START;
	}
} } } while ($@ =~ /^caught SIGWINCH/);

END { # atexit #
	unlink $lockfile;
	system "stty $save";
	system "tput cnorm";
	chomp(my $gettime=`date +%Y-%m-%d' '%T`);
	print INPUT "!! OMS exit at $gettime\n";
}
