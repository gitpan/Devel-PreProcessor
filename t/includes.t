#!/usr/bin/perl

use strict;
use Test;
BEGIN { plan tests => 1, todo => [] }

use Devel::PreProcessor qw( Includes );

local @INC = qw( ./lib );

select(STDERR);
Devel::PreProcessor::parse_file('t/includes.t');
select(STDOUT);

ok( 1 );

