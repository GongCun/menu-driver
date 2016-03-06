# menu-driver
A menu driver script for BOCM systems IPL

The first version was written by Micheal Cheong before 2011 with Korn Shell;
Raymond Chan updated and used it on many AIX machines in BOCM for IPL operation;
Gong Cun re-write it with Perl 5, make enhancement on the sign handle, log record, and curses-style operation but not using any additional perl module, only use some basic system tools (dd, stty, tput...), so it's very easy to migrate between *nix systems.

Please put the menu.pl, *.men on the same directory. The structure of *.men is very simple, only title, the options, and the commands.The title of menu must be the first line; the options must use '[0-9a-zA-Z])' in the beginning of the row, but can't use 'b', 'm' and 'x', because 'b' means "back to preview main", 'm' means "Go back to main menu", and 'x' means "exit". The commands correspond to the options but with the '[0-9a-zA-Z]@' in the beginning, if the action is go to another menu, please use the command "change_menu menu.men".

The following is the structure (see the detail on the .men file):
====================
The main menu

1) Goto the system menu.

2) Goto the stop menu.

3) Goto the start menu.

1@change_menu ./system.men
2@change_menu ./stop.men
3@change_menu ./start.men
======================
The stop menu

1) Backup the system.

2) Reboot the system.

1@sysback.ksh
2@reboot.ksh
=======================

The script was tested on AIX5,6,7 with Perl 5.

