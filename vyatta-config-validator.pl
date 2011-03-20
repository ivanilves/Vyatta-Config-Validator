#!/usr/bin/perl
#
# Validate Vyatta config.boot
#
use lib "/opt/vyatta/share/perl5/";
use Vyatta::Config;
use Vyatta::ConfigLoad;
use Vyatta::TypeChecker;

use strict;
use warnings;

my $config_file 	= "/opt/vyatta/etc/config/config.boot";
$config_file 		= $ARGV[0] if defined($ARGV[0]);

# get Vyatta config statements
my %config_hierarchy 	= getStartupConfigStatements($config_file);
my @config_set_nodes 	= @{ $config_hierarchy{set} };
if (scalar(@config_set_nodes) == 0) { exit 1; }

my $config              = new Vyatta::Config;

# need to convert Vyatta config statements into more convenient structure
my %all_set_nodes 	= ();
foreach (@config_set_nodes) {
  my ($node_ref)                = @$_;
  my $node_element_count        = scalar(@$node_ref);
  my @node_path_elements        = @$node_ref[0 .. ($node_element_count - 2)];
  my $node_path                 = join(' ', @node_path_elements);       $node_path =~ s/\'//g; @node_path_elements = split(/ /, $node_path);
  my $node_value                = @$node_ref[$node_element_count - 1];  $node_value =~ s/\'//g;

  # check if node is stub, i.e. has no value
  my $stub_node_path		= $node_path . " " . $node_value;
  my @stub_node_path_elements	= split(/ /, $stub_node_path);
  my $stub_node_tmpl_path	= $config->getTmplPath(\@stub_node_path_elements); 
  if (defined($stub_node_tmpl_path)) {
    @node_path_elements = @stub_node_path_elements;
    $node_path 		= $stub_node_path;
  }

  my @node_subpath_elements	= ();
  my $node_subpath              = '';
  my $node_element_number	= 0;
  foreach my $node_subpath_element (@node_path_elements) {
    @node_subpath_elements 	= (@node_subpath_elements, $node_subpath_element);
    $node_subpath		= join(' ', @node_subpath_elements);
    if (!defined($all_set_nodes{$node_subpath})) {
      if ($#node_subpath_elements eq $#node_path_elements) {
        $all_set_nodes{$node_subpath} = $node_value;
      } else {
        $all_set_nodes{$node_subpath} = $node_path_elements[$node_element_number+1];
      }
    }
    $node_element_number++;
  }
}

# now parsing our structure
my $validation_code 	= 0;
foreach (sort(keys(%all_set_nodes))) {
  my $node_path 		= $_;
  my @node_path_elements 	= split(/ /, $node_path);
  my $node_value		= $all_set_nodes{$node_path};
  my $node_tmpl_ref 		= $config->parseTmplAll($node_path);
  my $node_tmpl_path 		= $config->getTmplPath(\@node_path_elements);

  if (!defined($node_tmpl_path)) {
    warn(qq{$node_path: not a valid node path!} . "\n");
    $validation_code++;
  } else {
    if ((defined($node_tmpl_ref->{type})) && ($node_tmpl_ref->{type} ne 'txt')) {
      if (!validateType($node_tmpl_ref->{type}, $node_value, 1)) {
        warn(qq{$node_path: "$node_value" is not a valid value of type $node_tmpl_ref->{type}!} . "\n");
        $validation_code++;
      }
    } else {
      # try to apply extra validation, if node.def file exists
      my $node_tmpl_file 	= $node_tmpl_path . "/node.def";
      if ( -f $node_tmpl_file ) {
        open(TMPL_FILE, $node_tmpl_file); 
        my @tmpl_lines 	= <TMPL_FILE>; 
        close(TMPL_FILE);
        my @pattern_lines = grep(/syntax:expression:[ \t]+pattern[ \t]+\$VAR\(\@\)/, @tmpl_lines);
        my $pattern       = $pattern_lines[0];
        if (defined($pattern)) {
          $pattern =~ s/^.*\$VAR\(\@\)[ \t]*\"//; $pattern =~ s/\"[ \t]*;?.*$//; chomp($pattern);
          my $pattern_matches = Vyatta::ConfigLoad::match_regex($pattern, $node_value);
          if (!$pattern_matches) {
            warn(qq{$node_path: "$node_value" does not match regex /$pattern/} . "\n");
            $validation_code++;
          }
        }
      }
    } 
  }
}

exit($validation_code);
