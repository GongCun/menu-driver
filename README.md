# menu-driver
A menu driver script for BOCM systems IPL.

The first version was written by Micheal Cheong before 2011 with Korn Shell;
Raymond Chan updated and used it on most AIX machines in BOCM for IPL operation;
Gong Cun rewrited it in Perl, make enhancement on the signal handle, log record, paging output and curses-style operation.
This program don't use any additional perl module, so it's very easy to migrate between \*nix systems.

## General Usage ##

Just put the menu.pl, \*.men and script files (if you have) on the same directory.
The structure of \*.men is very simple, only the title, the options, and the commands.
The title of the menu must be on the first line.
The options must use a number or a letter, with ')' in the beginning of the row, but can't use 'b', 'm' and 'x'. Because 'b' means "back to preview main", 'm' means "Go back to main menu", and 'x' means "exit".
The commands correspond to the options use the same number or letter but with the '@' in the beginning, if the action is go to another menu, please use the command "change\_menu menu.men".

The following is the structure (see the detail on the .men file):
```bash
$ cat main.men
The main menu

1) Goto the system menu.

2) Goto the stop menu.

3) Goto the start menu.

1@change_menu ./system.men
2@change_menu ./stop.men
3@change_menu ./start.men

$ cat stop.men
The stop menu

1) Backup the system.

2) Reboot the system.

1@sudo -u root -p "Enter your password to confirm backup: " sysback.ksh
2@sudo -u root -p "Enter your password to confirm reboot: " reboot.ksh
```

If the sudo command is too long, you can put it in a file named "setAlias.ksh", the menu.pl will find the file and setup alias:
```bash
$ cat setAlias.ksh
alias -x SYSBACK='sudo -u root -p "Enter your password to confirm backup: " sysback.ksh'
alias -x REBOOT='sudo -u root -p "Enter your password to confirm reboot: " reboot.ksh'

$ cat stop.men
1) Backup the system.

2) Reboot the system.

1@SYSBACK
2@REBOOT
```

###Other tips###
Sometime we need page the program's output use 'more' or 'less', but if the program is interactive, the 'more' or 'less' will not work. So I add a keyword 'PAUSE' to paging the output and will not block the program if it needs to interact with user. It depends on a script written in expect: pty.exp. The effect is equivalent to using the 'script' command on MAC OS X or Linux:
```bash
$ script output.log [command]
$ more output.log
```

You can even use like this:
```bash
$ cat system.men
The system maintenance menu

1) Use root to do emergency maintenance

1@su - root; PAUSE
```

***The script was tested on AIX 5,6,7 with Perl 5.***

