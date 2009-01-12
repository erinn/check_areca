#!/usr/bin/env perl

#####################################################
#Program to check the areca RAID controller for the status of the RAID
#Created: 2007-11-27
#Version: 1.2.0              
#Revised: 2008-12-22
#Revised by: Erinn Looney-Triggs
#Author: Erinn Looney-Triggs
#Changelog:
#1.2: Added the ability to handle multiple RAID cards in a single host and
#fixed a couple of typos. Changed CL option areca_cli to arecacli to 
#better fit unix style.
#1.1: Fixed issue with newer versions of the Areca CLI > 1.72 and
#fixed a problem where the RAID name contained spaces 
#(Reported by Daniel Philipp). Also did a bit of cleanup.
#####################################################

use Carp;
use English qw( -no_match_vars );
use Getopt::Long;            #Grab command line switches
use Pod::Usage;
use strict;                  #Do it right
use warnings;

$ENV{PATH}      = '/usr/local/bin:/usr/bin:'; #Safer path
my $areca_cli   = '/usr/local/areca/bin/cli';
my $raid_cards  = '0' ;             #Default number of RAID cards to check
my $timeout     = '10';             #Default timeout of 10 seconds
my $VERSION     = '1.2.0';          #Version number

#Nagios plugin return values, in english
my $OK          = '0';
my $WARNING     = '1';
my $CRITICAL    = '2';
my $UNKNOWN     = '3';

GetOptions( 'arecacli|A=s'      => \$areca_cli,
            'cards|c=i'         => \$raid_cards,
            'man'               => sub { pod2usage(-verbose  => 2) },
            'timeout|t=i'       => \$timeout,
            'usage'             => sub { pod2usage(1) },
            'version'           => sub { VersionMessage() },
            'help'              => sub { pod2usage(1) },
);


#The heart of the matter
my @cli_output;

sanity_checks();

#If no count of raid cards is defined from the CL (default) then count them
unless ($raid_cards){
    $raid_cards = get_raid_card_count();
}


for my $card ($raid_cards){
    push @cli_output, check_areca($card) 
}

parse_areca(@cli_output);



sub check_areca{
    my $card_number = shift;
    my @output;
    
    #Build the command
    my $command = "sudo $areca_cli vsf info ctrl=$card_number";

    #Run the command
    @output = run_areca($command);
    
    #Pass the output back to be parsed
    return @output;  
}

sub get_raid_card_count{

    #Build the command
    my $command = "sudo $areca_cli main";
    
    #Run the command
    my @output = run_areca($command);
    
    #Find the right line(s).
    my @card_count = grep (/^Controller#\d+\(.*/, @output);
    
    #Areca starts at one for their count and so shall we
    return $#card_count +1;
}

sub parse_areca{
    my @output = @_;
    
    my $abnormal;       #Holds count of non-normal returns
    
    my @pertinent_lines = grep (/\s\d+\s/, @output);
    
    for my $line (@pertinent_lines){
        #Strip of leading spaces
        $line =~ s/^\s+//;
       
        #Split the line into discrete parts
        my ( $number, $level, $capacity, $state, ) 
            =  (split (/\s+/, "$line"))[0,-4,-3,-1];
 
        #If the state is normal continue on in loop
        if (lc $state eq "normal"){
            print "|Controller number: $number RAID level: $level "
            . "Capacity: $capacity State: $state| ";
        }
        
        #If state is abnormal continue on in loop but add 1 to $abnormal
        else{
            print "|Controller number: $number RAID level: $level "
            . "Capacity: $capacity State: $state| ";
            $abnormal++;
        }
    }
    
    #If any abnormalities exist exit with a critical error.
    if ($abnormal){
        exit $CRITICAL;
    }
    else {
        exit $OK;
    }
    
    return;     #This should never be reached
}

sub run_areca{
    my $command = shift;
    my @output;
    
    #Timer operation. Times out after $timeout seconds.
    eval {
    
        #Set the alarm and set the timeout
        local $SIG{ALRM} = sub { die "alarm\n" };
        alarm $timeout;
            
        #Run the command      
        @output = `$command`;
        if ($?){
            print "Command: \"$command\", failed"
                . "$OS_ERROR $CHILD_ERROR, aborting!\n";
            exit $CRITICAL;
        }
        
        #Reset the alarm if successful
        alarm 0;
    };
    
    #Test return value and exit if eval caught the alarm
    if ($EVAL_ERROR) {
        if ( $EVAL_ERROR eq "alarm\n" ) {
            print "Operation timed out after $timeout seconds.\n";
            exit $CRITICAL;
        }
        else {
            print "An unknown error has occured: $EVAL_ERROR \n";
            exit $UNKNOWN;
        }
    }
    
    return @output
}

sub sanity_checks{
    if (! -e $areca_cli){
        print "$areca_cli does not exist, aborting!\n";
        exit $CRITICAL;
    }
    if (! -x $areca_cli){
        print "$areca_cli is not executable by the running user, aborting!\n";
        exit $CRITICAL;
    }
    
    return;     #This should never be reached
}

#Version message information displayed in both --version and --help
sub main::VersionMessage {
    
    print <<"EOF";
This is version $VERSION of check_areca.

Copyright (c) 2007-2009 Erinn Looney-Triggs (erinn.looneytriggs\@gmail.com). 
All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License. 
See http://www.fsf.org/licensing/licenses/gpl.html

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. 

EOF

    exit 1;
}

__END__

=head1 NAME

check_areca - Checks the status of an Areca RAID via the Areca CLI utility.

=head1 VERSION

This documentation refers to check_areca version 1.2.0

=head1 USAGE

check_areca.pl

=head1 REQUIRED ARGUMENTS

None

=head1 OPTIONS

    --arecacli    (-A)     Set the location of the Areca cli executable. 
    --cards       (-c)     Set the number of RAID cards to be checked.
    --help                 Display usage information.
    --man                  Display the entire POD documentation     
    --timeout     (-t)     Sets the timeout, defaults to 10 seconds.
    --usage                Display usage information (same as --help)
    --version              Display the version number


=head1 DESCRIPTION
 
This is a Nagios plugin that runs the Areca CLI to check the status of the 
RAID controller. It then parses the resultant exit information and 
passes the output to NRPE. 

=head1 DIAGNOSTICS

=head2 Command: cli vsf info failed, aborting!

For some reason the command trying to be run failed. Try running it by hand
and seeing if it runs properly.

=head2 Operation timed out after <timeout> seconds.

Running the command failed after a certain amount of time (defaults to 10 
seconds). Try using the --timeout (-t) switch and increasing the timeout
threshold. Also try running the command by hand and see if it is hanging.

=head2 An unknown error has occurred:

Just what it says, running the cli command threw an unknown error and the 
process died. Run the CLI command by hand and see if you receive proper 
output.

=head2 <areca cli> does not exist, aborting!

The binary that the script is looking to run does not exist. By default 
check_areca looks in /usr/local/areca/bin/ for the cli. However, you can 
change this default by setting the --arecacli (-A) flag from the command
line

=head2 <areca cli> is not executable by the running user, aborting!

The cli program was found but it is not executable by the current user, 
usually this is the nagios user. 

=head1 CONFIGURATION AND ENVIRONMENT

The Areca cli program should be available on the system. By default 
check_areca looks in /usr/local/areca/bin/cli for the cli. You can set the 
location using the --arecacli (-A) flag from the command line.

If there is more than on RAID card on the system you can specify the number
of RAID cards to check via --cards (-c). However, this is not required
as there is autodetection code built in to try and figure out how 
many RAID cards are in the system. 

It is helpful to have an Areca RAID controller on the system being checked.
 
=head1 DEPENDENCIES
 
    check_areca depends on the following modules:
    POSIX           Standard Perl 5.8 module
    Getopt::Long    Standard Perl 5.8 module
    Pod::USAGE      Standard Perl 5.8 module       
    
=head1 INCOMPATIBILITIES

None known yet.

=head1 BUGS AND LIMITATIONS

It is possible that with a large number of RAID cards in a system that
the cli command will take longer than the 30 seconds that nagios is willing
to wait. This is not so much an issue with this script as with the cli
program, or the RAID card, or the bus, or...

If you encounter any bugs let me know. (erinn.looneytriggs@gmail.com)

=head1 AUTHOR

Erinn Looney-Triggs (erinn.looneytriggs@gmail.com)

=head1 LICENCE AND COPYRIGHT

Copyright (c) 2007-2009 Erinn Looney-Triggs (erinn.looneytriggs@gmail.com). 
All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License. 
See L<http://www.fsf.org/licensing/licenses/gpl.html>.
 
This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. 
