#!/usr/bin/perl

use strict;
use Test;
BEGIN { plan tests => 1, todo => [] }

use Devel::PreProcessor qw( Includes );

Devel::PreProcessor::parse_file('t/includes.t');

ok( 1 );

