package ModENCODE::Parser::IDF;

use Class::Std;
use Parse::RecDescent;
use Carp qw(croak carp);
use ModENCODE::Chado::CV;
use ModENCODE::Chado::CVTerm;
use ModENCODE::Parser::SDRF;
use ModENCODE::Chado::ProtocolAttribute;
use ModENCODE::Cache::Protocol;

use ModENCODE::ErrorHandler qw(log_error);

my %grammar     :ATTR;
my %idf_file    :ATTR( :init_arg<idf_file> );

sub new {
  my ($class, $idf_file) = @_;

  croak "Need an idf_file as the first argument to ModENCODE::Parser::IDF()" unless $idf_file;

  Class::Std::new($class, { 'idf_file' => $idf_file })
}

sub BUILD {
  my ($self, $ident, $args) = @_;

  $grammar{$ident} = <<'  GRAMMAR';
    {
      use Time::HiRes qw();
      use ModENCODE::ErrorHandler qw(log_error);
      use ModENCODE::Chado::Experiment;
      my $experiment = {};
      my $persons = {};
      my $instance = {};
      my $optional_metadata = {};
      my $protocols = {};
      my $term_sources = {};
      my $success = 1;
      my $experiment_obj = new ModENCODE::Chado::Experiment();
    }
    IDF:                                experiment
                                        optional_metadata(?)
                                        contact
                                        optional_metadata(?)
                                        experiment_instance(?)
                                        optional_metadata(?)
                                        protocol
                                        sdrf_file
                                        term_source
                                        end_of_file
                                        {
                                          $experiment_obj->add_properties($item[1]);
                                          my ($investigation_title_prop) = grep { $_->get_object->get_name() eq "Investigation Title" } @{$item[1]};
                                          $experiment_obj->set_uniquename(substr($investigation_title_prop->get_object->get_value(), 0, 235) . ":" . Time::HiRes::gettimeofday());
                                          if (defined($item[2])) { $experiment_obj->add_properties($item[2]->[0]); }
                                          $experiment_obj->add_properties($item[3]);
                                          if (defined($item[4])) { $experiment_obj->add_properties($item[4]->[0]); }
                                          if (defined($item[5])) { $experiment_obj->add_properties($item[5]->[0]); }
                                          if (defined($item[6])) { $experiment_obj->add_properties($item[6]->[0]); }
                                          return [$experiment_obj, $item[7], $item[8], $item[9], $success];
                                        }
                                        | <error>

  ##################################
  # Basic experiment metadata      #
  ##################################
  experiment:                           experiment_part(s)
                                        {
                                          # Convert experiment hash into experiment properties
                                          my @experiment_properties;
                                          if (!length($experiment->{'Investigation Title'}->[0])) {
                                            $success = 0;
                                            log_error "The Investigation Title field is missing from the IDF.";
                                            return;
                                          }
                                          push @experiment_properties, new ModENCODE::Chado::ExperimentProp({
                                              'experiment' => $experiment_obj,
                                              'value' => $experiment->{'Investigation Title'}->[0],
                                              'name' => 'Investigation Title',
                                              'type' => new ModENCODE::Chado::CVTerm({'name' => 'string', 'cv' => new ModENCODE::Chado::CV({'name' => 'xsd'})}),
                                            });
                                          if (defined($experiment->{'Experimental Design'})) {
                                            my $rank = 0;
                                            for (my $i = 0; $i < scalar(@{$experiment->{'Experimental Design'}}); $i++) {
                                              my $design_name = $experiment->{'Experimental Design'}->[$i];
                                              my $design_termsource = $experiment->{'Experimental Design Term Source REF'}->[$i];
                                              if (length($design_name)) {
                                                my $design_name_type = new ModENCODE::Chado::CVTerm({'name' => 'string', 'cv' => new ModENCODE::Chado::CV({'name' => 'xsd'})});
                                                my $design_name_dbxref;
                                                if (length($design_termsource)) {
                                                  $design_name_type = new ModENCODE::Chado::CVTerm({'name' => 'OntologyEntry', 'cv' => new ModENCODE::Chado::CV({'name' => 'MO'})});
                                                  $design_name_dbxref = new ModENCODE::Chado::DBXref({
                                                    'db' => new ModENCODE::Chado::DB({'name' => $design_termsource }),
                                                    'accession' => $design_name,
                                                  });
                                                }
                                                push @experiment_properties, new ModENCODE::Chado::ExperimentProp({
                                                    'experiment' => $experiment_obj,
                                                    'value' => $design_name,
                                                    'name' => 'Experimental Design',
                                                    'termsource' => $design_name_dbxref,
                                                    'type' => $design_name_type,
                                                    'rank' => $rank,
                                                  });
                                                $rank++;
                                              }
                                            }
                                          }
                                          if (defined($experiment->{'Experimental Factor Name'})) {
                                            for (my $i = 0; $i < scalar(@{$experiment->{'Experimental Factor Name'}}); $i++) {
                                              my $factor_name = $experiment->{'Experimental Factor Name'}->[$i];
                                              my $factor_type = $experiment->{'Experimental Factor Type'}->[$i];
                                              my $factor_type_termsource = $experiment->{'Experimental Factor Term Source REF'}->[$i];
                                              if (length($factor_name)) {
                                                push @experiment_properties, new ModENCODE::Chado::ExperimentProp({
                                                    'experiment' => $experiment_obj,
                                                    'value' => $factor_name,
                                                    'name' => 'Experimental Factor Name',
                                                    'type' => new ModENCODE::Chado::CVTerm({'name' => 'string', 'cv' => new ModENCODE::Chado::CV({'name' => 'xsd'})}),
                                                    'rank' => $i,
                                                  });
                                              }
                                              if (length($factor_type)) {
                                                my $factor_type_type = new ModENCODE::Chado::CVTerm({'name' => 'string', 'cv' => new ModENCODE::Chado::CV({'name' => 'xsd'})});
                                                my $factor_type_dbxref;
                                                if (length($factor_type_termsource)) {
                                                  $factor_type_type = new ModENCODE::Chado::CVTerm({'name' => 'OntologyEntry', 'cv' => new ModENCODE::Chado::CV({'name' => 'MO'})});
                                                  $factor_type_dbxref = new ModENCODE::Chado::DBXref({
                                                    'db' => new ModENCODE::Chado::DB({'name' => $factor_type_termsource}),
                                                    'accession' => $factor_type,
                                                  });
                                                }
                                                push @experiment_properties, new ModENCODE::Chado::ExperimentProp({
                                                    'experiment' => $experiment_obj,
                                                    'value' => $factor_type,
                                                    'name' => 'Experimental Factor Type',
                                                    'termsource' => $factor_type_dbxref,
                                                    'type' => $factor_type_type,
                                                    'rank' => $i,
                                                  });
                                              }
                                            }
                                          }

                                          $return = \@experiment_properties;
                                        }

  experiment_part:                      investigation_title
                                        | experimental_design
                                        | experimental_factor

  investigation_title_heading:          /Investigation *Title/i
  investigation_title:                  <skip:'[\r\n \t]*'> investigation_title_heading <skip:'[ "]*\t[ "]*'> field_value(s)
                                        { 
                                          $experiment->{'Investigation Title'} = [] if (!defined($experiment->{'Investigation Title'}));
                                          push @{$experiment->{'Investigation Title'}}, @{$item[4]};
                                        }

  experimental_design:                  experimental_design_name experimental_design_term_source_ref(?)
  experimental_design_name_heading:     /Experimental *Design/i
  experimental_design_name:             <skip:'[\r\n \t]*'> experimental_design_name_heading <skip:'[ "]*\t[ "]*'> field_value(s)
                                        { 
                                          $experiment->{'Experimental Design'} = [] if (!defined($experiment->{'Experimental Design'}));
                                          push @{$experiment->{'Experimental Design'}}, @{$item[4]};
                                        }
  experimental_design_termsource_heading: /Experimental *Design *Term *Source *REF/i
  experimental_design_term_source_ref:  <skip:'[\r\n \t]*'> experimental_design_termsource_heading <skip:'[ "]*\t[ "]*'> field_value(s)
                                        { 
                                          $experiment->{'Experimental Design Term Source REF'} = [] if (!defined($experiment->{'Experimental Design Term Source REF'}));
                                          push @{$experiment->{'Experimental Design Term Source REF'}}, @{$item[4]};
                                        }

  experimental_factor:                  experimental_factor_name experimental_factor_type(?) experimental_factor_term_source_ref(?)

  experimental_factor_name_heading:     /Experimental *Factor *Name/i
  experimental_factor_name:             <skip:'[\r\n \t]*'> experimental_factor_name_heading <skip:'[ "]*\t[ "]*'> field_value(s)
                                        { 
                                          $experiment->{'Experimental Factor Name'} = [] if (!defined($experiment->{'Experimental Factor Name'}));
                                          push @{$experiment->{'Experimental Factor Name'}}, @{$item[4]};
                                        }

  experimental_factor_type_heading:     /Experimental *Factor *Type/i
  experimental_factor_type:             <skip:'[\r\n \t]*'> experimental_factor_type_heading <skip:'[ "]*\t[ "]*'> field_value(s)
                                        { 
                                          $experiment->{'Experimental Factor Type'} = [] if (!defined($experiment->{'Experimental Factor Type'}));
                                          push @{$experiment->{'Experimental Factor Type'}}, @{$item[4]};
                                        }

  experimental_factor_termsource_heading: /Experimental *Factor *Term *Source *REF/i
  experimental_factor_term_source_ref:  <skip:'[\r\n \t]*'> experimental_factor_termsource_heading <skip:'[ "]*\t[ "]*'> field_value(s)
                                        { 
                                          $experiment->{'Experimental Factor Term Source REF'} = [] if (!defined($experiment->{'Experimental Factor Term Source REF'}));
                                          push @{$experiment->{'Experimental Factor Term Source REF'}}, @{$item[4]};
                                        }

  ##################################
  # Contact information/people     #
  ##################################
  contact:                              person_info(s?) person_role(s?)
                                        {
                                          # Convert contacts hash into experiment properties
                                          my @experiment_properties;
                                          if (defined($persons->{'Person Last Name'})) {
                                            for (my $i = 0; $i < scalar(@{$persons->{'Person Last Name'}}); $i++) {
                                              foreach my $person_attrib_name (keys(%$persons)) {
                                                next if $person_attrib_name eq 'Person Roles';
                                                next if $person_attrib_name eq 'Person Roles Term Source REF';
                                                my $person_attrib_value = $persons->{$person_attrib_name}->[$i];
                                                if (length($person_attrib_value)) {
                                                  push @experiment_properties, new ModENCODE::Chado::ExperimentProp({
                                                      'experiment' => $experiment_obj,
                                                      'value' => $person_attrib_value,
                                                      'name' => $person_attrib_name,
                                                      'type' => new ModENCODE::Chado::CVTerm({'name' => 'string', 'cv' => new ModENCODE::Chado::CV({'name' => 'xsd'})}),
                                                      'rank' => $i,
                                                    });
                                                }
                                              }
                                              my $person_roles = $persons->{'Person Roles'}->[$i];
                                              my $person_roles_termsource = $persons->{'Person Roles Term Source REF'}->[$i];
                                              if (length($person_roles)) {
                                                my $person_roles_type = new ModENCODE::Chado::CVTerm({'name' => 'string', 'cv' => new ModENCODE::Chado::CV({'name' => 'xsd'})});
                                                my $person_roles_dbxref;
                                                if (length($person_roles_termsource)) {
                                                  $person_roles_type = new ModENCODE::Chado::CVTerm({'name' => 'OntologyEntry', 'cv' => new ModENCODE::Chado::CV({'name' => 'MO'})});
                                                  $person_roles_dbxref = new ModENCODE::Chado::DBXref({
                                                      'db' => new ModENCODE::Chado::DB({'name' => $person_roles_termsource}),
                                                      'accession' => $person_roles,
                                                    });
                                                }
                                                push @experiment_properties, new ModENCODE::Chado::ExperimentProp({
                                                    'experiment' => $experiment_obj,
                                                    'value' => $person_roles,
                                                    'name' => 'Person Roles',
                                                    'termsource' => $person_roles_dbxref,
                                                    'type' => $person_roles_type,
                                                    'rank' => $i,
                                                  });
                                              }
                                            }
                                          }

                                          $return = \@experiment_properties;
                                        }

  person_info:                          person_name
                                        | person_email
                                        | person_phone
                                        | person_address
                                        | person_affiliation
                                        | person_role_name
                                        | person_role_term_source_ref

  person_name:                          person_last_name
                                        | person_first_name
                                        | person_mid_initial
  person_last_name_heading:             /Person *Last *Name/i
  person_last_name:                     <skip:'[\r\n \t]*'> person_last_name_heading <skip:'[ "]*\t[ "]*'> field_value(s?) <skip:'[ "]*\t[ "\n\r]*'>
                                        { 
                                          $persons->{'Person Last Name'} = [] if (!defined($persons->{'Person Last Name'}));
                                          push @{$persons->{'Person Last Name'}}, @{$item[4]};
                                        }
  person_first_name_heading:            /Person *First *Name/i
  person_first_name:                    <skip:'[\r\n \t]*'> person_first_name_heading <skip:'[ "]*\t[ "]*'> field_value(s?)  <skip:'[ "]*\t[ "\n\r]*'>
                                        { 
                                          $persons->{'Person First Name'} = [] if (!defined($persons->{'Person First Name'}));
                                          push @{$persons->{'Person First Name'}}, @{$item[4]};
                                        }
  person_mid_initial_heading:           /Person *Mid(dle)? *Initials?/i
  person_mid_initial:                   <skip:'[\r\n \t]*'> person_mid_initial_heading <skip:'[ "]*\t[ "]*'> field_value(s?) <skip:'[ "]*\t[ "\n\r]*'>
                                        { 
                                          $persons->{'Person Mid Initials'} = [] if (!defined($persons->{'Person Mid Initials'}));
                                          push @{$persons->{'Person Mid Initials'}}, @{$item[4]};
                                        }
  person_email_heading:                 /Person *Email *(Address)*/i
  person_email:                         <skip:'[\r\n \t]*'> person_email_heading <skip:'[ "]*\t[ "]*'> field_value(s?) <skip:'[ "]*\t[ "\n\r]*'>
                                        { 
                                          $persons->{'Person Email'} = [] if (!defined($persons->{'Person Email'}));
                                          push @{$persons->{'Person Email'}}, @{$item[4]};
                                        }
  person_phone_heading:                 /Person *Phone/i
  person_phone:                         <skip:'[\r\n \t]*'> person_phone_heading <skip:'[ "]*\t[ "]*'> field_value(s?) <skip:'[ "]*\t[ "\n\r]*'>
                                        { 
                                          $persons->{'Person Phone'} = [] if (!defined($persons->{'Person Phone'}));
                                          push @{$persons->{'Person Phone'}}, @{$item[4]};
                                        }
  person_address_heading:               /Person *Address/i
  person_address:                       <skip:'[\r\n \t]*'> person_address_heading <skip:'[ "]*\t[ "]*'> field_value(s?) <skip:'[ "]*\t[ "\n\r]*'>
                                        { 
                                          $persons->{'Person Address'} = [] if (!defined($persons->{'Person Address'}));
                                          push @{$persons->{'Person Address'}}, @{$item[4]};
                                        }
  person_affiliation_heading:           /Person *Affiliation/i
  person_affiliation:                   <skip:'[\r\n \t]*'> person_affiliation_heading <skip:'[ "]*\t[ "]*'> field_value(s?) <skip:'[ "]*\t[ "\n\r]*'>
                                        { 
                                          $persons->{'Person Affiliation'} = [] if (!defined($persons->{'Person Affiliation'}));
                                          push @{$persons->{'Person Affiliation'}}, @{$item[4]};
                                        }

  person_role:                          person_role_name
                                        | person_role_term_source_ref
  person_role_name_heading:             /Person *Roles?/i
  person_role_name:                     <skip:'[\r\n \t]*'> person_role_name_heading <skip:'[ "]*\t[ "]*'> field_value(s)
                                        { 
                                          $persons->{'Person Roles'} = [] if (!defined($persons->{'Person Roles'}));
                                          push @{$persons->{'Person Roles'}}, @{$item[4]};
                                        }
  person_role_termsource_heading:       /Person *Roles? *Term *Source *REF/i
  person_role_term_source_ref:          <skip:'[\r\n \t]*'> person_role_termsource_heading <skip:'[ "]*\t[ "]*'> field_value(s)
                                        { 
                                          $persons->{'Person Roles Term Source REF'} = [] if (!defined($persons->{'Person Roles Term Source REF'}));
                                          push @{$persons->{'Person Roles Term Source REF'}}, @{$item[4]};
                                        }

  ##################################
  # Experiment replicate info      #
  ##################################
  experiment_instance:                  experiment_instance_part(s)
                                        {
                                          # Convert experiment instances hash into experiment properties
                                          my @experiment_properties;
                                          if (defined($instance->{'Quality Control Type'})) {
                                            for (my $i = 0; $i < scalar(@{$instance->{'Quality Control Type'}}); $i++) {
                                              my $qc_type = $instance->{'Quality Control Type'}->[$i];
                                              my $qc_type_termsource = $instance->{'Quality Control Term Source REF'}->[$i];
                                              if (length($qc_type)) {
                                                my $qc_type_type = new ModENCODE::Chado::CVTerm({'name' => 'string', 'cv' => new ModENCODE::Chado::CV({'name' => 'xsd'})});
                                                my $qc_type_dbxref;
                                                if (length($qc_type_termsource)) {
                                                  $qc_type_type = new ModENCODE::Chado::CVTerm({'name' => 'OntologyEntry', 'cv' => new ModENCODE::Chado::CV({'name' => 'MO'})});
                                                  $qc_type_dbxref = new ModENCODE::Chado::DBXref({
                                                      'db' => new ModENCODE::Chado::DB({'name' => $qc_type_termsource}),
                                                      'accession' => $qc_type,
                                                    });
                                                }
                                                push @experiment_properties, new ModENCODE::Chado::ExperimentProp({
                                                    'experiment' => $experiment_obj,
                                                    'value' => $qc_type,
                                                    'name' => 'Quality Control Type',
                                                    'termsource' => $qc_type_dbxref,
                                                    'type' => $qc_type_type,
                                                    'rank' => $i,
                                                  });
                                              }
                                            }
                                          }
                                          if (defined($instance->{'Replicate Type'})) {
                                            for (my $i = 0; $i < scalar(@{$instance->{'Replicate Type'}}); $i++) {
                                              my $replicate_type = $instance->{'Replicate Type'}->[$i];
                                              my $replicate_type_termsource = $instance->{'Replicate Term Source REF'}->[$i];
                                              if (length($replicate_type)) {
                                                my $replicate_type_type = new ModENCODE::Chado::CVTerm({'name' => 'string', 'cv' => new ModENCODE::Chado::CV({'name' => 'xsd'})});
                                                my $replicate_type_dbxref;
                                                if (length($replicate_type_termsource)) {
                                                  $replicate_type_type = new ModENCODE::Chado::CVTerm({'name' => 'OntologyEntry', 'cv' => new ModENCODE::Chado::CV({'name' => 'MO'})});
                                                  $replicate_type_dbxref = new ModENCODE::Chado::DBXref({
                                                      'db' => new ModENCODE::Chado::DB({'name' => $replicate_type_termsource}),
                                                      'accession' => $replicate_type,
                                                    });
                                                }
                                                push @experiment_properties, new ModENCODE::Chado::ExperimentProp({
                                                    'experiment' => $experiment_obj,
                                                    'value' => $replicate_type,
                                                    'name' => 'Replicate Type',
                                                    'termsource' => $replicate_type_dbxref,
                                                    'type' => $replicate_type_type,
                                                    'rank' => $i,
                                                  });
                                              }
                                            }
                                          }
                                          $return = \@experiment_properties;
                                        }
  experiment_instance_part:             quality_control
                                        | replicate
                                        | date_of_experiment
                                        | release_date

  quality_control:                      quality_control_type quality_control_term_source_ref(?)
  quality_control_type_heading:         /Quality *Control *Type/i
  quality_control_type:                 <skip:'[\r\n \t]*'> quality_control_type_heading <skip:'[ "]*\t[ "]*'> field_value(s)
                                        { 
                                          $instance->{'Quality Control Type'} = [] if (!defined($instance->{'Quality Control Type'}));
                                          push @{$instance->{'Quality Control Type'}}, @{$item[4]};
                                        }
  quality_control_termsource_heading:   /Quality *Control *(Type)? *Term *Source *REF/i
  quality_control_term_source_ref:      <skip:'[\r\n \t]*'> quality_control_termsource_heading <skip:'[ "]*\t[ "]*'> field_value(s)
                                        { 
                                          $instance->{'Quality Control Term Source REF'} = [] if (!defined($instance->{'Quality Control Term Source REF'}));
                                          push @{$instance->{'Quality Control Term Source REF'}}, @{$item[4]};
                                        }

  replicate:                            replicate_type replicate_term_source_ref(?)
  replicate_type_heading:               /Replicate *Type/i
  replicate_type:                       <skip:'[\r\n \t]*'> replicate_type_heading <skip:'[ "]*\t[ "]*'> field_value(s)
                                        { 
                                          $instance->{'Replicate Type'} = [] if (!defined($instance->{'Replicate Type'}));
                                          push @{$instance->{'Replicate Type'}}, @{$item[4]};
                                        }
  replicate_termsource_heading:         /Replicate *(Type)? *Term *Source *REF/i
  replicate_term_source_ref:            <skip:'[\r\n \t]*'> replicate_termsource_heading <skip:'[ "]*\t[ "]*'> field_value(s)
                                        { 
                                          $instance->{'Replicate Term Source REF'} = [] if (!defined($instance->{'Replicate Term Source REF'}));
                                          push @{$instance->{'Replicate Term Source REF'}}, @{$item[4]};
                                        }

  ##################################
  # Optional metadata              #
  ##################################
  optional_metadata:                    optional_metadata_part(s)
                                        {
                                          # Convert experiment optional_metadatas hash into experiment properties
                                          my @experiment_properties;
                                          if (defined($optional_metadata->{'Date of Experiment'}) && length($optional_metadata->{'Date of Experiment'}->[0])) {
                                            push @experiment_properties, new ModENCODE::Chado::ExperimentProp({
                                                'experiment' => $experiment_obj,
                                                'value' => $optional_metadata->{'Date of Experiment'}->[0],
                                                'type' => new ModENCODE::Chado::CVTerm({'name' => 'date', 'cv' => new ModENCODE::Chado::CV({'name' => 'xsd'})}),
                                                'name' => 'Date of Experiment',
                                              });
                                          }
                                          if (defined($optional_metadata->{'Public Release Date'}) && length($optional_metadata->{'Public Release Date'}->[0])) {
                                            push @experiment_properties, new ModENCODE::Chado::ExperimentProp({
                                                'experiment' => $experiment_obj,
                                                'value' => $optional_metadata->{'Public Release Date'}->[0],
                                                'type' => new ModENCODE::Chado::CVTerm({'name' => 'string', 'cv' => new ModENCODE::Chado::CV({'name' => 'xsd'})}),
                                                'name' => 'Public Release Date',
                                              });
                                          }
                                          if (defined($optional_metadata->{'PubMed ID'}) && length($optional_metadata->{'PubMed ID'}->[0])) {
                                            push @experiment_properties, new ModENCODE::Chado::ExperimentProp({
                                                'experiment' => $experiment_obj,
                                                'value' => $optional_metadata->{'PubMed ID'}->[0],
                                                'type' => new ModENCODE::Chado::CVTerm({'name' => 'string', 'cv' => new ModENCODE::Chado::CV({'name' => 'xsd'})}),
                                                'name' => 'PubMed ID',
                                              });
                                          }
                                          if (defined($optional_metadata->{'Project'}) && length($optional_metadata->{'Project'}->[0])) {
                                            my $rank = 0;
                                            foreach my $project_group (@{$optional_metadata->{'Project'}}) {
                                              push @experiment_properties, new ModENCODE::Chado::ExperimentProp({
                                                  'experiment' => $experiment_obj,
                                                  'value' => $project_group,
                                                  'type' => new ModENCODE::Chado::CVTerm({'name' => 'string', 'cv' => new ModENCODE::Chado::CV({'name' => 'xsd'})}),
                                                  'name' => 'Project',
                                                  'rank' => $rank++,
                                                });
                                            }
                                          }
                                          if (defined($optional_metadata->{'Lab'}) && length($optional_metadata->{'Lab'}->[0])) {
                                            my $rank = 0;
                                            foreach my $project_lab (@{$optional_metadata->{'Lab'}}) {
                                              push @experiment_properties, new ModENCODE::Chado::ExperimentProp({
                                                  'experiment' => $experiment_obj,
                                                  'value' => $project_lab,
                                                  'type' => new ModENCODE::Chado::CVTerm({'name' => 'string', 'cv' => new ModENCODE::Chado::CV({'name' => 'xsd'})}),
                                                  'name' => 'Lab',
                                                  'rank' => $rank++,
                                                });
                                            }
                                          }
                                          if (defined($optional_metadata->{'Experiment Description'}) && length($optional_metadata->{'Experiment Description'}->[0])) {
                                            my $description = $optional_metadata->{'Experiment Description'}->[0];
                                            if ($description !~ m,^http://,) {
                                              $description = "http://wiki.modencode.org/project/index.php?title=" . $description;
                                            }
                                            push @experiment_properties, new ModENCODE::Chado::ExperimentProp({
                                                'experiment' => $experiment_obj,
                                                'value' => $description,
                                                'type' => new ModENCODE::Chado::CVTerm({'name' => 'string', 'cv' => new ModENCODE::Chado::CV({'name' => 'xsd'})}),
                                                'name' => 'Experiment Description',
                                              });
                                          }
                                          $optional_metadata = {};
                                          $return = \@experiment_properties;
                                        }
  optional_metadata_part:               pubmed_id | experiment_description_ref | submitting_project

  pubmed_id_heading:                    /PubMed *ID/i
  pubmed_id:                            <skip:'[\r\n \t]*'> pubmed_id_heading <skip:'[ "]*\t[ "]*'> field_value(s?) <skip:'[ "]*\t[ "\n\r]*'>
                                        { 
                                          $optional_metadata->{'PubMed ID'} = [] if (!defined($optional_metadata->{'PubMed ID'}));
                                          push @{$optional_metadata->{'PubMed ID'}}, @{$item[4]};
                                        }
  experiment_description_ref_heading:   /Experiment *Description *(REF)?/i
  experiment_description_ref:           <skip:'[\r\n \t]*'> experiment_description_ref_heading <skip:'[ "]*\t[ "]*'> field_value(s?) <skip:'[ "]*\t[ "\n\r]*'>
                                        { 
                                          $optional_metadata->{'Experiment Description'} = [] if (!defined($optional_metadata->{'Experiment Description'}));
                                          push @{$optional_metadata->{'Experiment Description'}}, @{$item[4]};
                                        }
  submitting_project:                   submitting_project_group(?) submitting_project_subgroup(?)
  submitting_project_group_heading:     /Project *Group|Project(?!\s*Subgroup)/i
  submitting_project_group:             <skip:'[\r\n \t]*'> submitting_project_group_heading <skip:'[ "]*\t[ "]*'> field_value(s?) <skip:'[ "]*\t[ "\n\r]*'>
                                        { 
                                          $optional_metadata->{'Project'} = [] if (!defined($optional_metadata->{'Project'}));
                                          push @{$optional_metadata->{'Project'}}, @{$item[4]};
                                        }
  submitting_project_subgroup_heading:  /Project *Subgroup|Lab/i
  submitting_project_subgroup:          <skip:'[\r\n \t]*'> submitting_project_subgroup_heading <skip:'[ "]*\t[ "]*'> field_value(s?) <skip:'[ "]*\t[ "\n\r]*'>
                                        { 
                                          $optional_metadata->{'Lab'} = [] if (!defined($optional_metadata->{'Lab'}));
                                          push @{$optional_metadata->{'Lab'}}, @{$item[4]};
                                        }

  date_of_experiment_heading:           /Date *of *Experiment/i
  date_of_experiment:                   <skip:'[\r\n \t]*'> date_of_experiment_heading <skip:'[ "]*\t[ "]*'> field_value(s?) <skip:'[ "]*\t[ "\n\r]*'>
                                        { 
                                          $optional_metadata->{'Date of Experiment'} = [] if (!defined($optional_metadata->{'Date of Experiment'}));
                                          push @{$optional_metadata->{'Date of Experiment'}}, @{$item[4]};
                                        }
  release_date_heading:                 /(Public)? *Release *Date/i
  release_date:                         <skip:'[\r\n \t]*'> release_date_heading <skip:'[ "]*\t[ "]*'> field_value(s?) <skip:'[ "]*\t[ "\n\r]*'>
                                        { 
                                          $optional_metadata->{'Public Release Date'} = [] if (!defined($optional_metadata->{'Public Release Date'}));
                                          push @{$optional_metadata->{'Public Release Date'}}, @{$item[4]};
                                        }


  ##################################
  # Protocol information           #
  ##################################
  protocol:                             protocol_part(s)
                                        {
                                          # Convert protocols hash into protocol objects
                                          my @protocols;
                                          if (defined($protocols->{'Protocol Name'})) {
                                            for (my $i = 0; $i < scalar(@{$protocols->{'Protocol Name'}}); $i++) {
                                              my $protocol_name = $protocols->{'Protocol Name'}->[$i];
                                              next unless length($protocol_name);
                                              # Manually create a CachedObject here because we're going to be using the SDRF
                                              # protocol as the "official" cached protocol
                                              my $protocol_obj = new ModENCODE::Chado::Protocol({'name' => $protocol_name});

                                              my $protocol_description = $protocols->{'Protocol Description'}->[$i];
                                              if (length($protocol_description)) {
                                                $protocol_obj->get_object->set_description($protocol_description);
                                              }

                                              ####################################################
                                              my $protocol_type = $protocols->{'Protocol Type'}->[$i];
                                              my $protocol_type_termsource = $protocols->{'Protocol Type Term Source REF'}->[$i];
                                              if (!length($protocol_type)) {
                                                $success = 0;
                                                log_error "The Protocol Type field for $protocol_name is missing from the IDF.";
                                                return;
                                              }
                                              if (!length($protocol_type_termsource)) {
                                                $success = 0;
                                                log_error "The Protocol (Type) Term Source REF field for $protocol_name is missing from the IDF.";
                                                return;
                                              }
                                              my @protocol_types = split(/[;,]+/, $protocol_type);
                                              for (my $i = 0; $i < scalar(@protocol_types); $i++) { $protocol_types[$i] =~ s/^\s*|\s*$//g; }
                                              my @protocol_type_types = split(/[;,]+/, $protocol_type_termsource);
                                              for (my $i = 0; $i < scalar(@protocol_type_types); $i++) { $protocol_type_types[$i] =~ s/^\s*|\s*$//g; }
                                              if (scalar(@protocol_types) >= 1) {
                                                my $rank = 0;
                                                foreach my $protocol_type (@protocol_types) {
                                                  my ($cv, $name) = split(/:/, $protocol_type);
                                                  if (!$name) {
                                                    if (scalar(@protocol_type_types) == 1) {
                                                      $name = $cv;
                                                      $cv = $protocol_type_types[0];
                                                      if (scalar(@protocol_types) > 1) {
                                                        log_error "Each term in Protocol Type REALLY SHOULD have a prefix if there is more than one type, even if there is only one term source ref (e.g. $cv:$name).", "warning";
                                                      }
                                                    } else {
                                                      $success = 0;
                                                      log_error "Each term in Protocol Type must have a prefix if there is more than one term source (e.g. MO:grow, SO:gene).";
                                                      return;
                                                    }
                                                  }
                                                  my @matching_source = grep { $_ eq $cv } @protocol_type_types;
                                                  if (!scalar(@matching_source)) {
                                                    $success = 0;
                                                    log_error "The term source $cv for Protocol Type '$protocol_type' is not mentioned in the Protocol Term Source REF field.";
                                                    return;
                                                  } else {
                                                    my $protocol_type_type = new ModENCODE::Chado::CVTerm({'name' => 'OntologyEntry', 'cv' => new ModENCODE::Chado::CV({'name' => 'MO'})});
                                                    my $protocol_type_dbxref = new ModENCODE::Chado::DBXref({
                                                        'db' => new ModENCODE::Chado::DB({'name' => $cv}),
                                                        'accession' => $name,
                                                      });
                                                    my $protocol_type_obj = new ModENCODE::Chado::ProtocolAttribute({
                                                        'heading' => 'Protocol Type',
                                                        'value' => $name,
                                                        'termsource' => $protocol_type_dbxref,
                                                        'type' => $protocol_type_type,
                                                        'rank' => $rank,
                                                        'protocol' => $protocol_obj,
                                                      });
                                                    $protocol_obj->get_object->add_attribute($protocol_type_obj);
                                                  }
                                                  $rank++;
                                                }
                                              }
                                              ####################################################

                                              my $protocol_parameters = $protocols->{'Protocol Parameters'}->[$i];
                                              if (length($protocol_parameters)) {
                                                my $protocol_parameters_obj = new ModENCODE::Chado::ProtocolAttribute({
                                                    'heading' => 'Protocol Parameters',
                                                    'value' => $protocol_parameters,
                                                    'type' => new ModENCODE::Chado::CVTerm({
                                                        'name' => 'string',
                                                        'cv' => new ModENCODE::Chado::CV({
                                                            'name' => 'xsd',
                                                          }),
                                                      }),
                                                    'protocol' => $protocol_obj,
                                                  });
                                                $protocol_obj->get_object->add_attribute($protocol_parameters_obj);
                                              }

                                              push @protocols, $protocol_obj;
                                            }
                                          }
                                          $return = \@protocols;
                                        }
  protocol_part:                        protocol_name
                                        | protocol_type
                                        | protocol_description
                                        | protocol_parameters
                                        | protocol_term_source_ref

  protocol_name_heading:                /Protocol *Name/i
  protocol_name:                        <skip:'[\r\n \t]*'> protocol_name_heading <skip:'[ "]*\t[ "]*'> field_value(s)
                                        { 
                                          $protocols->{'Protocol Name'} = [] if (!defined($protocols->{'Protocol Name'}));
                                          push @{$protocols->{'Protocol Name'}}, @{$item[4]};
                                        }
  protocol_type_heading:                /Protocol *Type/i
  protocol_type:                        <skip:'[\r\n \t]*'> protocol_type_heading <skip:'[ "]*\t[ "]*'> field_value(s?)
                                        { 
                                          $protocols->{'Protocol Type'} = [] if (!defined($protocols->{'Protocol Type'}));
                                          push @{$protocols->{'Protocol Type'}}, @{$item[4]};
                                        }
  protocol_description_heading:         /Protocol *Description/i
  protocol_description:                 <skip:'[\r\n \t]*'> protocol_description_heading <skip:'[ "]*\t[ "]*'> field_value(s?)
                                        { 
                                          $protocols->{'Protocol Description'} = [] if (!defined($protocols->{'Protocol Description'}));
                                          push @{$protocols->{'Protocol Description'}}, @{$item[4]};
                                        }
  protocol_parameters_heading:          /Protocol *Parameters?/i
  protocol_parameters:                  <skip:'[\r\n \t]*'> protocol_parameters_heading <skip:'[ "]*\t[ "]*'> field_value(s?)
                                        { 
                                          $protocols->{'Protocol Parameters'} = [] if (!defined($protocols->{'Protocol Parameters'}));
                                          push @{$protocols->{'Protocol Parameters'}}, @{$item[4]};
                                        }
  protocol_ref_heading:                 /Protocol *(Type)? *Term *Source *REF/i
  protocol_term_source_ref:             <skip:'[\r\n \t]*'> protocol_ref_heading <skip:'[ "]*\t[ "]*'> field_value(s)
                                        { 
                                          $protocols->{'Protocol Type Term Source REF'} = [] if (!defined($protocols->{'Protocol Type Term Source REF'}));
                                          push @{$protocols->{'Protocol Type Term Source REF'}}, @{$item[4]};
                                        }

  ##################################
  # SDRF file                      #
  ##################################
  sdrf_file_heading:                    /SDRF *File/i
  sdrf_file:                            <skip:'[\r\n \t]*'> sdrf_file_heading <skip:'[ "]*\t[ "]*'> field_value(s)
                                        { 
                                          my @sdrf_experiments;
                                          foreach my $sdrf_file (@{$item[4]}) {
                                            next unless (length($sdrf_file));
                                            log_error "Parsing SDRF '$sdrf_file'.", "notice", ">";
                                            my $sdrf_parser = new ModENCODE::Parser::SDRF();
                                            my $sdrf_experiment = $sdrf_parser->parse($sdrf_file);
                                            if (!$sdrf_experiment) {
                                              log_error "Failed.", "error", "<";
                                              $success = 0;
                                              return;
                                            }
                                            log_error "Done.", "notice", "<";
                                            push @sdrf_experiments, $sdrf_experiment;
                                          }
                                          $return = \@sdrf_experiments;
                                        }

  ##################################
  # Term Source references         #
  ##################################
  term_source:                          term_source_part(s)
                                        {
                                          # Convert term sources hash into dbxref objects
                                          my @dbxrefs;
                                          if (defined($term_sources->{'Term Source Name'})) {
                                            for (my $i = 0; $i < scalar(@{$term_sources->{'Term Source Name'}}); $i++) {
                                              my $term_source_name = $term_sources->{'Term Source Name'}->[$i];
                                              next unless length($term_source_name);
                                              my $term_source_obj = new ModENCODE::Chado::DB({'name' => $term_source_name});

                                              my $term_source_file = $term_sources->{'Term Source File'}->[$i];
                                              if (length($term_source_file)) {
                                                $term_source_obj->get_object->set_url($term_source_file);
                                              }
                                              my $term_source_type = $term_sources->{'Term Source Type'}->[$i];
                                              if (length($term_source_type)) {
                                                $term_source_obj->get_object->set_description($term_source_type);
                                              }

                                              my $term_source_version = $term_sources->{'Term Source Version'}->[$i];
                                              $term_source_version = undef if (!length($term_source_version));
                                              my $term_obj = new ModENCODE::Chado::DBXref({
                                                'db' => $term_source_obj,
                                                'accession' => '__ignore',
#                                                'version' => $term_source_version,
                                              });
                                              # Add a CV so we can validate any Term Source REFfed fields from the SDRF
                                              ModENCODE::Config::get_cvhandler()->add_cv($term_source_name, $term_source_file, $term_source_type);

                                              push @dbxrefs, $term_obj;
                                            }
                                          }
                                          $return = \@dbxrefs;
                                        }
  term_source_part:                     term_source_name
                                        | term_source_file
                                        | term_source_version
                                        | term_source_type
  term_source_name_heading:             /Term *Source *Name/i
  term_source_name:                     <skip:'[\r\n \t]*'> term_source_name_heading <skip:'[ "]*\t[ "]*'> field_value(s)
                                        { 
                                          $term_sources->{'Term Source Name'} = [] if (!defined($term_sources->{'Term Source Name'}));
                                          push @{$term_sources->{'Term Source Name'}}, @{$item[4]};
                                        }
  term_source_file_heading:             /Term *Source *(File|URL|URI)/i
  term_source_file:                     <skip:'[\r\n \t]*'> term_source_file_heading <skip:'[ "]*\t[ "]*'> field_value(s)
                                        { 
                                          $term_sources->{'Term Source File'} = [] if (!defined($term_sources->{'Term Source File'}));
                                          push @{$term_sources->{'Term Source File'}}, @{$item[4]};
                                        }
  term_source_version_heading:          /Term *Source *Version/i
  term_source_version:                  <skip:'[\r\n \t]*'> term_source_version_heading <skip:'[ "]*\t[ "]*'> field_value(s?) <skip:'[ "]*\t[ "\n\r]*'>
                                        { 
                                          $term_sources->{'Term Source Version'} = [] if (!defined($term_sources->{'Term Source Version'}));
                                          push @{$term_sources->{'Term Source Version'}}, @{$item[4]};
                                        }
  term_source_type_heading:             /Term *Source *Type/i
  term_source_type:                     <skip:'[\r\n \t]*'> term_source_type_heading <skip:'[ "]*\t[ "]*'> field_value(s)
                                        { 
                                          $term_sources->{'Term Source Type'} = [] if (!defined($term_sources->{'Term Source Type'}));
                                          push @{$term_sources->{'Term Source Type'}}, @{$item[4]};
                                        }

  ##################################
  # Basic parsing terms            #
  ##################################
  field_value:                          /([^\t"\n\r]*[ "]*)/
                                        { 
                                          my $trimmed_val = $1;
                                          $trimmed_val =~ s/^\s*|\s*$//g;
                                          $return = $trimmed_val; 
                                        }

  end_of_file:                          <skip:'[\r\n \t]*'> /([\s\r\n]*)$/

  GRAMMAR

}
sub parse {
  my ($self) = @_;
     
  my $idf_file = $idf_file{ident $self};
  log_error "Reading IDF file from $idf_file.", "notice", ">";
  my $document;
  if ( -r $idf_file ) {
    local $/;
    if (!open(FH, "<$idf_file")) {
      log_error "Couldn't read file $idf_file";
      return 0;
    }
    $document = <FH>;
    close FH;
  } else {
    log_error "Can't find file '$idf_file'";
    return 0;
  }

  # Clean up some cross-platform issues in the IDF
  $document =~ s/\A [" ]*/\t/gxms;
  $document =~ s/\t"/\t/gxms;
  $document =~ s/"\t/\t/gxms;
  $document =~ s/^"|"$//gxms;
  my $parser = $self->_get_parser();
  log_error "Done.", "notice", "<";
  
  log_error "Parsing IDF file $idf_file.", "notice", ">";
  my $result = $parser->IDF($document);
  my $success = pop(@$result);
  log_error "Done.", "notice", "<";
  return 0 unless $success;
  return $result;
}

sub _get_parser : RESTRICTED {
  my ($self) = @_;
  $::RD_ERRORS = 1;
  $::RD_WARN = undef;
  $::RD_TRACE = undef;
  $::RD_HINT = 1;
  $::RD_AUTOSTUB = undef;
  $Parse::RecDescent::skip = '[ "]*\t[ "]*';
  my $parser = new Parse::RecDescent($grammar{ident $self});
}


1;
