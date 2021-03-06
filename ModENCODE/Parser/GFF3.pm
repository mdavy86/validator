package ModENCODE::Parser::GFF3;

=pod

=head1 NAME

ModENCODE::Parsers::GFF3 - Customized GFF3 parser for ModENCODE.

=head1 SYNOPSIS

This class provides a customized GFF3 parser for use by ModENCODE.  It will
parse GFF3 and return an array of ModENCODE::Chado::Feature objects, for
each subgroup within in the GFF3 input (delimited by '###').  Note that
it does NOT parse all GFF3 elements and makes certain assumptions about the
GFF3 input.  This should NOT be used a generic GFF3 parser.  Due to an issue
with circular references between Feature and FeatureRelationship objects
make sure to explicitly call Feature::DESTROY() otherwise it will lead
to a memory leak.

=head1 USAGE

=over

 my $gff3_input_handle;
 my $builds_information_hash_ref;
 ## create an instance of the parser
 my $parser = new ModENCODE::Parser::GFF3({
 	gff3	=> $gff3_input_handle,
 	$builds	=> $builds_information_hash_ref
 });
 ## get the iterator for parsing data
 my $iterator = $parser->iterator();
 while ($iterator->has_next()) {
 	my @feature_sub_group = $iterator->next();
 	foreach my $feature (@feature_sub_group) {
 		## do something with each ModENCODE::Chado::Feature
 		## object
 	}
 }

=back
 
=head1 CONSTRUCTOR

=over

=item ModENCODE::Parser::GFF3::new({ gff3 => $gff3_input_handle,
				     builds => $builds_information_hash_ref,
				     source_prefix => $source_prefix });

Arguments to the constructor should be contained within a hash reference.
The required arguments are:

	gff3 - reference to input handle for GFF3 data
	builds - reference to a multi-dimensional hash containing:

=over

$builds{$source}{$build_name}{$genomic_region}{$tag}{$value}
Required $tag values are:

	start	- start coordinate of genomic region
	end	- end coordinate of genomic region
	type	- type of genomic region (e.g. contig)

=back

=back

The optional arguments are:

	source_prefix - prefix to append to Analysis.program in the form:
		        $source_prefix:$source

=back

=head1 METHODS

=over

=item ModENCODE::Parser::GFF3::iterator()

Returns an instance of ModENCODE::Parser::GFF3::Iterator for iterating through
ach subgroup in the GFF3 input.

=item ModENCODE::Parser::GFF3::Iterator::has_next()

Returns true if there are subgroups left to iterate over.

=item ModENCODE::Parser::GFF3::Iterator::next()

Returns an array of populated ModENCODE::Chado::Feature objects.
Due to an issue with circular references between Feature and
FeatureRelationship objects make sure to explicitly call
Feature::DESTROY() otherwise it will lead to a memory leak.


=back

=head1 SEE ALSO

L<ModENCODE::Chado::Feature>

=head1 AUTHOR

Ed Lee L<mailto:elee@berkeleybop.org>, ModENCODE DCC
L<http://www.modencode.org>.

=cut

use strict;
use warnings;

use IO::File;

use ModENCODE::Chado::Feature;
use ModENCODE::Chado::FeatureLoc;
use ModENCODE::Chado::FeatureRelationship;
use ModENCODE::Chado::FeatureProp;
use ModENCODE::Chado::CVTerm;
use ModENCODE::Chado::CV;
use ModENCODE::Chado::Analysis;
use ModENCODE::Chado::AnalysisFeature;
use ModENCODE::Chado::Organism;
use ModENCODE::Cache;
use ModENCODE::ErrorHandler qw(log_error);

my $CV;

sub new
{
	my $class = shift;
        $CV = new ModENCODE::Chado::CV({ 'name' => "SO" });
	my $this = {};
	bless $this, $class;
	my $params = shift;

	$this->{builds} = $params->{builds};
	$this->{id_callback} = $params->{id_callback};
	if (my $file = $params->{gff3}) {
		if (ref $file) {
			$this->{gff3} = $file;
		}
		else {
			$this->{gff3} = new IO::File($file) ||
				die "Error reading $file: $!";
		}
	}
	else {
		die "No GFF3 file passed";
	}
	$this->{source_prefix} = $params->{source_prefix};
	$this->{counter} = 0;
	return $this;
}

sub parse
{
	my $this = shift;
	my $gff3 = $this->{gff3};
	my $builds = $this->{builds};
	my %features = ();
	$this->cleanup_cache();
	while (my $line = <$gff3>) {
                if ($. % 10000 == 0) {
                  log_error "Reading line #$..", "notice";
                }
		chomp $line;
		last if $line eq "###";
    if ($line =~ /^##genome-build\s+([\w-]+)\s+([\w\.]+)/) {
			my $src = $1;
			my $build_name = $2;
      # SPECIAL CASE for D. mel : if it's a specific build within r5, strip the build id.
      # The genome-builds file uses only the assembly number.
      if( ($src eq "FlyBase") && ($build_name =~ /^r5\..+$/) ) {
        log_error "Setting FlyBase build $build_name to r5 for consistency.", "notice" ;
        $build_name = "r5" ; 
      }
			$this->{build} = $builds->{$src}->{$build_name} ||
				die "Build data for $line not found";
			next;
		}
		## ignore comments (or any other directives)
		elsif ($line =~ /^#/) {
			next;
		}
		## ignore lines with only white space
		elsif ($line =~ /^\s*$/) {
			next;
		}

		my @fields = split(/\t/, $line);
		die "Invalid number of fields: " . scalar(@fields)
			if scalar(@fields) != 9;
		my ($seqid, $source, $type, $start, $end, $score, $strand,
			$phase, $attrs_field) = @fields;

                die "Field 9 must be of the form var=val (or ID=name), not just" .
                " a string like $attrs_field" 
                  if (length($attrs_field) > 0 && $attrs_field !~ /=/);

		my @tokens = split(/;/, $attrs_field);
		my %attrs = ();
		foreach my $token (@tokens) {
			my ($key, $value) = split(/=/, $token);
			push @{$attrs{$key}}, split(/,/, $value) if $value;
		}

		my $name = $attrs{Name}->[0];

                my $id = &{$this->{id_callback}}($this, $attrs{ID}->[0], $name,
                        $seqid, $source, $type, $start, $end, $score, $strand,
                        $phase) if ($this->{id_callback});

                # Fall back to generating ID ourselves if callback didn't do it
		$id ||= $attrs{Name}->[0] || sprintf("ID%.6d", ++($this->{counter}));

		## can't have duplicate ids within the same file
                # Unless, of course, they're Wormbase CDSes, which by convention all
                # have the same ID for a given gene (but multiple locations)
                die "Duplicate id $id found" if ($this->{$id}++ && $type ne "CDS");


                my $orig_seqid = $seqid;
                my $seqid_uniq = &{$this->{id_callback}}($this, $seqid, $seqid, $seqid, $source) if ($this->{id_callback});
                $seqid = $seqid_uniq if ($seqid_uniq eq $id);
                my $src_feature = undef;
                my $add_as_srcfeature = 0;
                if ($seqid ne $id) { 
                  $src_feature = $this->get_src_feature($seqid);
                } else {
                  # Self-located features can be used as source features later
                  $add_as_srcfeature = 1;
                }

                my $organism;
                if ($src_feature && $src_feature->get_object->get_organism()) {
                        $organism = $src_feature->get_object->get_organism;
                } else {
                        # Just get the first organism from the first seqfeature
                        die "No genome-build directive found" unless $this->{build};
                        $organism =
                        $this->create_organism(
                          [values(%{$this->{build}})]->[0]->{'organism'}
                        );
                }

		$name = $attrs{Name}->[0] || $id;
		my $feature = $this->create_feature($id, $name, $type, $organism);
                if ($add_as_srcfeature) {
                  # Self-located features can be used as source features later
                  $this->{src_features}->{$orig_seqid} = $feature;
                }
                # Add feature properties
                foreach my $attr_name (keys(%attrs)) {
                    if ($attr_name ne "Note") {
                      next unless $attr_name =~ m/^[a-z]/;
                    }
                    next if $attr_name eq "gene";
                    next if $attr_name eq "parental_relationship";
                    next if $attr_name eq "normscore";
                    if ($attr_name eq "external_evidence") {
                      foreach my $attr_value (@{$attrs{$attr_name}}) {
                        if ($attr_value =~ /^(modENCODE)_/) {
                          my ($sub_id) = ($attr_value =~ /modENCODE_(\d+)/);
                          my $feature_dbxref = new ModENCODE::Chado::DBXref({
                              'accession' => $attr_value,
                              'db' => new ModENCODE::Chado::DB({
                                  'name' => 'modencode_submission',
                                  'url' => $sub_id,
                                  'description' => 'modencode_submission'
                                })
                            });
                          $feature->get_object->add_dbxref($feature_dbxref);
                        } else {
                          log_error "Unknown external_evidence ID type \"$attr_name\" in GFF. Not creating DBXref.", "warning";
                        }
                      }
                    }

                    my $rank = 0;
                    foreach my $attr_value (@{$attrs{$attr_name}}) {
                        my $featureprop = $this->create_feature_prop(
                                $attr_value,
                                $rank++, 
                                new ModENCODE::Chado::CVTerm({
                                        name => $attr_name,
                                        cv => new ModENCODE::Chado::CV({ name => 'GFF' }),
                                        dbxref => new ModENCODE::Chado::DBXref({ 
                                            accession => $attr_name, 
                                            db => new ModENCODE::Chado::DB({ 
                                                'name' => 'GFF',
                                                'description' => 'database'
                                              }),
                                          })
                        }));
                        $feature->get_object->add_property($featureprop);
                    }
                }


		## have valid seq loc
		if ($start =~ /^\d+$/ && $end =~ /^\d+$/) {
                        my $locrank = $this->{$id} if $type eq "CDS";
			my $feature_loc =
				$this->create_feature_loc($start, $end, $strand,
						$src_feature, undef, $locrank);
			$feature->get_object->add_location($feature_loc);
                        $feature->get_object->dirty();
		}
		## have a hit
		if (my $target = $attrs{Target}->[0]) {
			my ($target_id, $target_start, $target_end,
				$target_strand) = split(/ /, $target);

                        if (!$features{$target_id}) {
                                $target_id = &{$this->{id_callback}}($this, $target_id) 
                                if ($this->{id_callback});
                        }

			my $target_feature = $features{$target_id} ||
				die "No feature found for target $target_id";
			$target_strand = "+" if !$target_strand;

                        my $residue_info = $attrs{Gap}->[0] if $attrs{Gap};
                        if (!($target_start =~ /^\d+$/ && $target_end =~ /^\d+$/)) {
                          die "Provided a target missing a start and/or end: $target";
                        }

			my $target_feature_loc =
				$this->create_feature_loc($target_start,
							  $target_end,
							  $target_strand,
							  $target_feature,
                                                          $residue_info);
			$target_feature_loc->set_rank(1);
			$feature->get_object->add_location($target_feature_loc);
                        $feature->get_object->dirty();
			$feature->get_object->set_is_analysis(1);
			my $analysis_feature =
				$this->create_analysis_feature($score,
							       $source, 
                                                               $feature);
                        if (defined($attrs{'normscore'}->[0])) {
                          $analysis_feature->set_normscore($attrs{'normscore'}->[0]);
                        }
			$feature->get_object->add_analysisfeature($analysis_feature);
                        $feature->get_object->dirty();
		} elsif ($score ne '.') {
                        my $analysis_feature =
                                $this->create_analysis_feature($score, 
                                                               $source,
                                                               $feature);
                        if (defined($attrs{'normscore'}->[0])) {
                          $analysis_feature->set_normscore($attrs{'normscore'}->[0]);
                        }
			$feature->get_object->add_analysisfeature($analysis_feature);
                        $feature->get_object->dirty();
                }
		my $parents = $attrs{Parent};
		if ($parents) {
			my %relationships;
			my $parental_relationship =
				$attrs{parental_relationship};
			if ($parental_relationship) {
				foreach my $r (@{$parental_relationship}) {
					my ($rel, $parent) = split('/', $r);
                                        die "Malformed parental relationship" unless ($rel && $parent);
					$relationships{$parent} = $rel;
				}
			}
			my $rank = 0;
			foreach my $object_id (@{$parents}) {
				my $rel_type = $relationships{$object_id} ||
					"part_of";
                                if (!$features{$object_id}) {
                                        $object_id = &{$this->{id_callback}}($this, $object_id) 
                                        if ($this->{id_callback});
                                }
				my $object = $features{$object_id} ||
					die "$object_id for relationship  " .
					"with $id not found";
				my $feature_relationship =
					$this->create_feature_relationship(
						$feature,
						$object, $rel_type, \$rank);
				$feature->get_object->add_relationship(
					$feature_relationship);
                                $feature->get_object->dirty();
				$object->get_object->add_relationship(
					$feature_relationship);
                                $object->get_object->dirty();
			}
		}
                if (my $prediction_status = $attrs{'prediction_status'}->[0]) {
                        my $prediction_prop = $this->create_feature_prop(
                                $prediction_status,
                                0, 
                                new ModENCODE::Chado::CVTerm({
                                        name => 'prediction_status',
                                        cv => new ModENCODE::Chado::CV({ name => 'modencode' }),
                        }));
                        $feature->get_object->add_property($prediction_prop);
                }

		$features{$feature->get_object->get_uniquename()} = $feature;
	}
	return values %features;
}

sub create_feature
{
	my $this = shift;
	my ($uniquename, $name, $type, $organism) = @_;

        $type = $this->create_cvterm($type);

        my $feature;
        if ($feature = ModENCODE::Cache::get_feature_by_uniquename_and_type(
            $uniquename, $type)) {
                log_error "Found already created feature $uniquename to represent feature in GFF.", "debug";
          if ($organism->get_id == $feature->get_object->get_organism_id) {
                log_error "  Using it because unique constraints are identical.", "debug";
                return $feature;
          } else {
                log_error "The previously seen feature \"" . $feature->get_object->get_uniquename . "\"" .
                " of type \"" . $feature->get_object->get_type(1)->get_name() . "\"" . 
                " was created with <i>" . $feature->get_object->get_organism(1)->to_string . "</i>" .
                " as an organism, rather than the GFF's <i>" . $organism->get_object->to_string . "</i>" .
                ". Assuming the original organism is correct!", "warning";
                $organism = $feature->get_object->get_organism();
          }
        }

        $feature = new ModENCODE::Chado::Feature({
            'uniquename' => $uniquename,
            'type' => $type,
            'name' => $name,
            'organism' => $organism,
          });
	return $feature;
}

sub create_cvterm
{
	my $this = shift;
	my $type = shift;
	my $cvterm = new ModENCODE::Chado::CVTerm({	name => $type,
							cv => $CV });
	return $cvterm;
}

sub create_organism
{
        my ($this, $genus, $species) = @_;
        ($genus, $species) = split(/ +/, $genus, 2) unless $species;
        my $organism = new ModENCODE::Chado::Organism({
            'genus' => $genus,
            'species' => $species,
          });
        return $organism;
}

sub create_feature_loc
{
	my $this = shift;
	my ($start, $end, $strand, $src_feature, $residue_info, $rank) = @_;
        if ($start && $end && ($end < $start)) {
          die "Start ($start) is less than end ($end)";
        }
	if ($strand !~ /^\d+/) {
		if ($strand eq "+") {
			$strand = 1;
		}
		elsif ($strand eq "-") {
			$strand = -1;
		}
		else {
			$strand = 0;
		}
	}
	my $feature_loc = new ModENCODE::Chado::FeatureLoc();
	$feature_loc->set_fmin($start - 1) if defined($start);
	$feature_loc->set_fmax($end) if defined($end);
	$feature_loc->set_strand($strand);
	$feature_loc->set_residue_info($residue_info);
	$feature_loc->set_srcfeature($src_feature) if $src_feature;
	$feature_loc->set_rank($rank) if defined($rank);
	return $feature_loc;
}

sub create_feature_prop
{
	my $this = shift;
	my ($value, $rank, $type) = @_;
        $rank ||= 0;
        my $feature_prop = new ModENCODE::Chado::FeatureProp({
                        value => $value,
                        rank => $rank,
                        type => $type,
                });
	return $feature_prop;
}

sub create_feature_relationship
{
	my $this = shift;
	my ($subject, $object, $type, $rank) = @_;
	my $feature_relationship =
		new ModENCODE::Chado::FeatureRelationship({
                    'subject' => $subject,
                    'object' => $object,
                    'type' => $this->create_cvterm($type),
                    'rank' => ${$rank}++,
                    });
	return $feature_relationship;
}

sub create_analysis_feature
{
	my $this = shift;
	my ($score, $source, $feature) = @_;
	my $analysis = $this->{analysis}->{$source};
	if (!$analysis) {
		$analysis = new ModENCODE::Chado::Analysis({
                    'program' => ($this->{source_prefix} ?  $this->{source_prefix} . ":$source" : $source),
                    'programversion' => 1,
                  });
		$this->{analysis}->{$source} = $analysis;
	}
        $score = undef if $score eq ".";
	my $analysis_feature = new ModENCODE::Chado::AnalysisFeature({
            'analysis' => $analysis,
            'rawscore' => $score,
          });
	return $analysis_feature;
}

sub get_src_feature
{
	my $this = shift;
	my $id = shift;
	my $build = $this->{build} || die "No genome-build directive found";
	my $src_feature = $this->{src_features}->{$id};
	if (!$src_feature) {
                my $build_data = $build->{$id} || die "No build info for $id found";
                die "No source feature created for $id, and no build data" if $build_data == 1;
                if (!$build_data->{type}) {
                  use Data::Dumper;
                  print Dumper($build_data);
                  die "No SO type in genome-build definition for " . $id;
                }
		$src_feature =
			$this->create_feature($id, $id, $build_data->{type},
                          $this->create_organism($build_data->{organism}));
		$this->{src_features}->{$id} = $src_feature;
		if (!(defined $build_data->{start}) ||
			!(defined $build_data->{end})) {
			die "Missing start/end coordinate for genomic region " .
				$id;
		}
		my $feature_loc =
			$this->create_feature_loc($build_data->{start},
			$build_data->{end}, 1);
		$src_feature->get_object->add_location($feature_loc);
                $src_feature->get_object->dirty();
	}
	return $src_feature;
}

sub cleanup_cache
{
	my $this = shift;
	delete $this->{src_features};
	delete $this->{analysis};
}

sub iterator
{
	my $this = shift;
	return ModENCODE::Parser::GFF3::Iterator->new($this);
}

package ModENCODE::Parser::GFF3::Iterator;

sub new
{
	my $class = shift;
	my $parser = shift;
	my $this = {};
	bless $this, $class;
	$this->{parser} = $parser;
	return $this;
}

sub has_next
{
	my $this = shift;
	return !$this->{parser}->{gff3}->eof();
}

sub next
{
	my $this = shift;
	return $this->{parser}->parse();
}

1;
