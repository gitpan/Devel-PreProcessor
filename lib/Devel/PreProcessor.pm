#!/usr/local/bin/perl -s

### Devel::PreProcessor - Module inlining and other Perl source manipulations

### Copyright 1998 Evolution Online Systems, Inc.
  # You may use this software for free under the terms of the Artistic License

### To Do:
  # - Create a real test suite.

### Change History
  # 1998-09-19 Cleaned up format of POD documentation.
  # 1998-09-08 Updated documentation to cover @INC overrides.
  # 1998-06-30 Added comment about handling "no" statements.
  # 1998-05-23 Added support for overriding @INC.
  # 1998-03-24 Minor doc fixup.
  # 1998-02-24 Removed leading whitespace from POD regexes (thanks Del)
  # 1998-02-23 Changed regex for use statements to break at parenthesis.
  # 1998-02-19 Moved general-purpose code to new Devel::PreProcessor package.
  # 1998-02-19 Added $Conditionals mechanism.
  # 1998-02-19 Added $INC{$module} to output to prevent run-time reloads.
  # 1998-01-26 Modified to imports and eval in the same begin block. 
  # 1998-01-20 Hacked ActiveWare source; changed pragma import calls -Simon

package Devel::PreProcessor;

$VERSION = 1998.09_19;

# Option flags, defaulting to off
use vars qw( $Includes $Conditionals $StripComments $StripPods $ShowFileBoundaries $StripBlankLines );

# Devel::PreProcessor->import( 'StripPods', 'Conditionals', ... );
sub import {
  my $package = shift;
  foreach ( @_ ) {
    if ( m/Conditionals/i ) {
      $Conditionals = 1;
    } elsif ( m/Includes/i ) {
      $Includes = 1;
    } elsif ( m/StripComments/i ) {
      $StripComments = 1;
    } elsif ( m/ShowFileBoundaries/i ) {
      $ShowFileBoundaries = 1;
    } elsif ( m/StripBlankLines/i ) {
      $StripBlankLines = 1;
    } elsif ( m/StripPods/i ) {
      $StripPods = 1;
    } elsif ( m/LibPath:(.*)/i ) {
      @INC = split(/\:/, $1);
    } else {
      die "unkown import";
    }
  }
}

# If we're being run directly, expand the first file on the command line.
unless ( caller ) {
  $Includes ||= $main::Includes;
  $Conditionals ||= $main::Conditionals;
  $StripComments ||= $main::StripComments;
  $StripBlankLines ||= $main::StripBlankLines;
  $StripPods ||= $main::StripPods;
  $ShowFileBoundaries ||= $main::ShowFileBoundaries;
  my $source = shift @ARGV;
  @INC = @ARGV if ( scalar @ARGV );
  parse_file($source);
}

### File Processing

# parse_file( $filename );
sub parse_file {
  my $filename = shift;
  
  open(FH, $filename);
  my $line_number;
  
  LINE: while(<FH>) {
    $line_number ++;
    
    if ( $line_number < 2 and /^\#\!/ ){
      print $_;  			# don't discard the shbang line
      next LINE;
    } 
      
    elsif ( $StripPods and /^=(pod|head[12])/i ){
      do { ++ $line_number; } 
	  while ( <FH> !~ /^=cut/i );  # discard everything up to '=cut'
      next LINE;
    }    
    elsif ( /^=(pod|head[12])/i ){
      do { print $_; ++ $line_number; $_ = <FH> } 
	  while ( $_ !~ /^=cut/i );  	# include everything up to '=cut'
      next LINE;
    }
    
    elsif ( $Includes and /^\s*use\s+([^\s\(]+)(?:\s*(\S.*))?;/ ) {
      my( $module, $import ) = ( $1, $2 );
      do_use($module, $import) or print $_;
    } elsif ( $Includes and /^\s*require\s+([^\$]+);/ ) {
      my $module = $1;
      do_require( $module ) or print $_;
    } elsif ( $Includes and /^\s*__(END|DATA)__/ ){
      last LINE;			    # discard the rest of the file
    }
    
    elsif ( $StripBlankLines and /^\s*$/){
      next LINE;			    # skip whitespace only lines
    }
    
    elsif ( $StripComments and /^\s*\#/){
      next LINE;			    # skip full-line comments
    }
    
    elsif ( $Conditionals and /^\s*#__CONDITIONAL__ if (.*)/i ) {
      my $rc = eval "package main;\n" . $1;
      unless ( $rc and ! $@ ) {	    # if expr isn't true, skip to end
	do { ++ $line_number; print "\n"; } 
	    while ( <FH> !~ /^\s*\#__CONDITIONAL__ endif/i );
      }
    } elsif ( $Conditionals and /^\s*\#__CONDITIONAL__ endif/i){
      next LINE;			    # skip conditional end
    } elsif ( $Conditionals and /^\s*\#__CONDITIONAL__  (.*)/i){
      print $1;			            # remove conditional null branches
      next LINE;
    } else {
      print $_;
    }
  }
}

# do_use( $module, $import_list );
sub do_use {
  my $module = shift;
  my $imports = shift;
  
  return 1 if ($module eq 'strict');  # problems with scoping of strict
  
  if ($module eq 'lib') {
    my @paths = eval "$imports";
    push @INC, @paths unless $@;
    return 0;
  }
  
  my $filename = find_file_once( $module );
  return if ( ! $filename ) ;
  
  print "BEGIN { \n";
  
  do_include( $module, $filename ) unless ( $filename eq '-1' );
  
  # Call import, but don't use the OOP notation for lowercase/pragmas.
  print $module, 
  	($module =~ /\A[a-z]+\Z/ ? "::import('$module', " : "->import("), 
	( defined $imports ? $imports : '' ), ");\n";
  
  print "}\n";
  
  return 1;
}

# do_require( $module );
sub do_require {
  my $module = shift;
  
  my $filename = find_file_once( $module );
  return if ( ! $filename or $filename eq '-1' ) ;
  do_include( $module, $filename );
}

# do_include( $module, $filename );
sub do_include {
  my $module = shift;
  my $filename = shift;
  
  print "### Start of inlined library $module.\n" . 
	"  # Source file $filename.\n"          if $ShowFileBoundaries;

  print "\$INC{'$module'} = '$filename';\n";
  print "eval {\n";
  parse_file($filename);
  print "\n};\n";

  print "### End of inlined library $module.\n" if $ShowFileBoundaries;
  
  return 1;
}

# %files_found - hash of filenames included so far
use vars qw( %files_found );

# $filename_or_nothing = find_file_once($module);
sub find_file_once {
  my $module_file = shift;
  
  return if ($module_file =~ /^[\.\_\d]+/); # ignore Perl version requirements
  
  $module_file =~ s#::#/#g;
  $module_file .= '.pm';
  
  # If we've already included this file, we don't need to do it again.
  return -1 if $files_found{ $module_file };
  my $filename = search_path( $module_file );
  $files_found{ $module_file } ++ if ( $filename );
  return $filename;
}

# $filename = search_path($module);
sub search_path {
  my $module = shift;
  
  my $dir;
  foreach $dir (@INC) {
    my $match = $dir . "/" . $module;
    return $match if ( -e $match );
  }
  
  return 0;
}

1;

__END__

=head1 NAME

Devel::PreProcessor - Module inlining and other Perl source manipulations


=head1 SYNOPSIS

From a command line,

    sh> perl Devel/PreProcessor.pm -Flags sourcefile > targetfile

Or in a Perl script,

    use Devel::PreProcessor qw( Flags );
    
    select(OUTPUTFH);
    Devel::PreProcessor::parse_file( $source_pathname );


=head1 DESCRIPTION

This package processes Perl source files and outputs a modified version acording to several user-setable option flags, as detailed below.

Each of the flag names listed below can be used as above, with a hyphen on the command line, or as one of the arguments in an import statement. Each of these flags are mapped to the scalar package variable of the same name.

=over 4

=item Includes

If true, parse_file will attempt to replace C<use> and C<require> statements with inline declarations containg the source of the relevant library found in the current @INC. The resulting script should operate identically and no longer be dependant on external libraries (but see compatibility note below).

If a C<use libs ...> statement is encountered in the source, the library path arguments are evaluated and pushed onto @INC at run-time to enable inclusion of libraries from these paths.

=item ShowFileBoundaries

If true, comment lines will be inserted delimiting the start and end of each inlined file.

=item StripPods

If true, parse_file will not include POD from the source files. All groups of lines resembling the following will be discarded:

    =(pod|head1|head2)
    ...
    =cut

=item StripBlankLines

If true, parse_file will skip lines that are empty, or that contain only whitespace. 

=item StripComments

If true, parse_file will not include full-line comments from the source files. Only lines that start with a pound sign are discarded; this behaviour might not match Perl's parsing rules in some cases, such as multiline strings.

=item Conditionals

If true, parse_file will utilize a simple conditional inclusion scheme, as follows.

    #__CONDITIONAL__ if expr
    ...		
    #__CONDITIONAL__ endif

The provided Perl expression is evaluated, and unless it is true, everything up to the next endif declaration is replaced with empty lines. In order to allow the default behavour to be provided when running the raw files, comment out lines in non-default branches with the following:

    #__CONDITIONAL__ ...

Empty lines are used  in place of skipped blocks to make line numbers come out evenly, but conditional use or require statements will throw the count off, as we don't pad by the size of the file that would have been in-lined.

The conditional functionality can be combined with Perl's C<-s> switch, which allows you to set flags on the command line, such as:

    perl -s Devel/PreProcessor.pm -Conditionals -Switch filter.test

You can use any name for your switch, and the matching scalar variable will be set true; the following code will only be used if you supply the argument as shown below.

    #__CONDITIONAL__ if $Switch
    #__CONDITIONAL__   print "you hit the switch!\n";
    #__CONDITIONAL__ endif

=back

=head1 EXAMPLES

To inline all used modules:

    perl -s Devel/PreProcessor.pm -Includes foo.pl > foo_complete.pl

To count the lines of Perl source in a file, run the preprocessor from a shell with the following options

    perl -s Devel/PreProcessor.pm -StripComments -StripPods -StripBlankLines foo.pl | wc -l


=head1 BUGS AND CAVEATS

=over 4

=item Compatibility: Includes

Libraries inlined with Includes may not be appropriate on another system, eg, if Config is inlined, the script may fail if run on a platform other than that on which it was built.

=item Bug: Use statements can't span lines

Should support newline in import blocks for multiline use statements.

=item Limitation: No support for unimporting with "no" statements.

Should be mapped to unimport statements. Correct handling of pragmas to be determined.

=item Limitation: Autosplit files not included

It should be possible to find and include autosplit file fragments.

=item Limitation: XSUB files not included

There's not much we can do about XSub/PLL files.

=item Bug: __DATA__ lost

We should really preserve the __DATA__ block from the original source file.

=back


=head1 PREREQUISITES AND INSTALLATION

This package should run on any standard Perl 5 installation.

You may retrieve this package from the below URL:
  http://www.evoscript.com/dist/Devel-PreProcessor-1998.0919.tar.gz

To install this package, download and unpack the distribution archive, then:

=over 4

=item * C<perl Makefile.PL>

=item * C<make test>

=item * C<make install>

=back


=head1 STATUS AND SUPPORT

This release of Devel::PreProcessor is intended for public review and feedback. 
It has been tested in several environments and no major problems have been 
discovered, but it should be considered "alpha" pending that feedback.

  Name            DSLI  Description
  --------------  ----  ---------------------------------------------
  Devel::
  ::PreProcessor  adpf  Module inlining and other Perl source manipulations

Further information and support for this module is available at E<lt>www.evoscript.comE<gt>.

Please report bugs or other problems to E<lt>bugs@evoscript.comE<gt>.


=head1 AUTHORS AND COPYRIGHT

Copyright 1998 Evolution Online Systems, Inc. E<lt>www.evolution.comE<gt>

You may use this software for free under the terms of the Artistic License. 

Contributors: 
M. Simon Cavalletto E<lt>simonm@evolution.comE<gt>, 
with feature suggestions from Del Merritt E<lt>dmerritt@intranetics.comE<gt> 
and Win32 debugging assistance from Randy Roy.

Derived from filter.pl, as provided by ActiveWare <www.activestate.com>

=cut
