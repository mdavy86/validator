package ModENCODE::Parser::SDRF;
=pod

=head1 NAME

ModENCODE::Parser::IDF - Parser and grammar validator for the IDF file for a
BIR-TAB data package.

=head1 SYNOPSIS

This module applies a L<Parse::RecDescent> grammar to a BIR-TAB SDRF document
and converts it into a barebones L<ModENCODE::Chado::Experiment> representing
the data and metadata in the SDRF.

For more information on the BIR-TAB file formats, please see:
L<http://wiki.modencode.org/project/index.php/BIR-TAB_specification>.

=head1 USAGE

  my $parser = new ModENCODE::Parser::SDRF();
  my $experiment = $parser->parse("/path/to/sdrf_file.tsv");
  print $experiment->to_string();

The format for a valid BIR-TAB SDRF document is more thoroughly covered in the
BIR-TAB specification, but you may be able to glean some additional information
from examining the grammar defined in this module. Some coverage of the
conventions used in this module's L<Parse::RecDescent> grammar is therefore
worthwhile.

L<Parse::RecDescent> is a top-down recursive-descent text parser. The basic
style is:

  Atom_Name: atom_definition { $return = "Result: " . $item[1]; }

Where atom_definition can any number of other atom names or regular expressions,
among other things. (See the full L<RecDescent|Parse::RecDescent> documentation
for more information.)

The top-level feature in this SDRF parser is the C<SDRF_header> element, which
is only designed to parse the header row of an SDRF document. Unlike
L<ModENCODE::Parser::IDF>, the grammar is not used to process the entire
document. Rather, the grammar is used to parse the header row and generate a
function that will act as a parser on each row of data. The basic approach is:

  open SDRF, $sdrf_file;
  my $header_parser = $self->_get_parser();
  my ($row_parser, $number_of_protocols) = $header_parser->SDRF_header(<SDRF>);
  my @row_objs;
  while (<SDRF>) {
    my @cells = map { s/^"|"$//g; $_; } split(/\t/, $_);
    push @row_objs, &{$row_parser}($self, \@cells);
  }

  # MERGE @row_objs INTO MINIMAL NUMBER OF APPLIED PROTOCOLS
  
  $experiment = new ModENCODE::Chado::Experiment({
    'applied_protocol_slots' => \@merged_row_objs
  });

  return $experiment;

What's actually happening is that each atom that actually matches a column
heading (as opposed to atoms that just consist of other atoms) is returning a
reference to a function that can turn values in that column into the proper
L<ModENCODE::Chado|index> object. In fact, I<every> atom is returning a function
reference; the lowest-level ones parse the contents of a cell into a
L<ModENCODE::Chado|index> object, the higher level ones pull the objects from
the lower level ones into a parent object (for example, the function generated
by the C<protocol> atom returns a L<ModENCODE::Chado::AppliedProtocol> object which
itself contains L<ModENCODE::Chado::Data> objects which were generated by the
C<input_or_output> atom listed in the C<protocol> atom definition.

Rather than include all of the object-creation code in the grammar definition,
the atoms utilize C<$self-E<gt>create_E<lt>objectE<gt>(...)> where C<object> is
C<protocol> or some other L<ModENCODE::Chado|index> type. These functions are
wrapped inside a function closure that attaches any of the information from the
header row necessary to the creation of the object for the data rows. For
instance, an attribute column may have a heading C<Attribute [thing]>. The
function closure generated is:

  sub {
    my ($self, $values) = @_;
    my $value = shift(@$values);
    return $self->create_attribute(
      $value,      # Pulled from the data cell as passed to the function
      $item[1],    # The heading of the attribute: "Attribute", included by closure
      $item[3][0], # The name of the attribute: "thing", included by closure
      $item[5][0], # The type of the attribute, undef, included by closure
      $item[7],    # The term source of the attribute, another function
      $values,     # The rest of the cells in this row, to be passed to the
                   #  term-source generation function, for instance
  }

=head1 FUNCTIONS

=over

=item parse($document)

Attempt to parse the SDRF file referenced by the filename passed in as
C<$document>. Returns 0 on failure, otherwise returns a
L<ModENCODE::Chado::Experiment> object containing the
L<ModENCODE::Chado::AppliedProtocol>s described by the SDRF. (For more
information on the data structure built, see
L<ModENCODE::Chado::Experiment/Applied Protocols>.) In addition to the data
defined in the SDRF, "anonymous" data are generated to link applied protocols
that would otherwise break the experiment chain. 

=item create_datum($heading, $value, $name, $type, $termsource, $attributes, $values)

Create a L<ModENCODE::Chado::Data> object with a heading of C<$heading>, a name
of C<$name>, a type L<CVTerm|ModENCODE::Chado::CVTerm> from the string in
C<$type> a value of C<$value>, a term source L<DBXref|ModENCODE::Chado::DBXref>
object in C<$termsource>, and any L<ModENCODE::Chado::Attribute> columns in
C<$attributes>. The C<$values> input is the array of the remaining columns in
the data row after C<$value> has been C<shift>ed off the front.

=item create_protocol($name, $termsource, $attributes, $data, $values)

Create a L<ModENCODE::Chado::Protocol> object with a name of C<$name>, a term
source L<DBXref|ModENCODE::Chado::DBXref> object in C<$termsource>, and any
L<ModENCODE::Chado::Attribute> columns in C<$attributes>. The C<$values> input
is the array of the remaining columns in the data row after C<$value> has been
C<shift>ed off the front.

=item create_termsource($termsource_ref, $accession, $values)

Create a L<ModENCODE::Chado::DBXref> object for a term source defined in the IDF
with a I<Term Source REF> of C<$termsource_ref> and an accession number in
C<$accession>. The C<$values> input is the array of the remaining columns in
the data row after C<$value> has been C<shift>ed off the front.

=back

=head1 SEE ALSO

L<Class::Std>, L<Parse::RecDescent>, L<ModENCODE::Validator::IDF_SDRF>,
L<ModENCODE::Parser::IDF>, L<ModENCODE::Chado::Experiment>,
L<ModENCODE::Chado::Protocol>, L<ModENCODE::Chado::DBXref>,
L<ModENCODE::Chado::AppliedProtocol>,
L<http://wiki.modencode.org/project/index.php/BIR-TAB_specification>

=head1 AUTHOR

E.O. Stinson L<mailto:yostinso@berkeleybop.org>, ModENCODE DCC
L<http://www.modencode.org>.

=cut
use strict;

use Class::Std;
use Parse::RecDescent;
use Carp qw(croak carp);
use Data::Dumper;

use ModENCODE::Chado::AppliedProtocol;
use ModENCODE::Chado::Protocol;
use ModENCODE::Chado::Data;
use ModENCODE::Chado::DB;
use ModENCODE::Chado::DBXref;
use ModENCODE::Chado::CV;
use ModENCODE::Chado::CVTerm;
use ModENCODE::Chado::Attribute;
use ModENCODE::Chado::Experiment;
use ModENCODE::ErrorHandler qw(log_error);

my %grammar     :ATTR;

sub BUILD {
  my ($self, $ident, $args) = @_;

  $grammar{$ident} = <<'  GRAMMAR';
    {
      use Carp qw(croak);
      use ModENCODE::ErrorHandler qw(log_error);
      my $success = 1;
    }
    SDRF_header:                        input_or_output(s?) protocol(s) end_of_line
                                        { 
                                          if ($success) {
                                            $return = [ 
                                              sub {
                                                my ($self, $line) = @_;

                                                # Get inputs that come before the first protocol. This 
                                                # is mainly for biomaterials
                                                my @extra_inputs;
                                                foreach my $sub (@{$item[1]}) {
                                                  if (ref $sub eq 'CODE') {
                                                    push @extra_inputs, &$sub($self, $line);
                                                  } else {
                                                    croak "Not a sub for parsing: $sub\n";
                                                  }
                                                }

                                                # Parse everything else (the protocols)
                                                my @protocols;
                                                foreach my $sub (@{$item[2]}) {
                                                  if (ref $sub eq 'CODE') {
                                                    push @protocols, &$sub($self, $line);
                                                  } else {
                                                    croak "Not a sub for parsing: $sub\n";
                                                  }
                                                }
                                                if (scalar(@$line)) {
                                                  log_error "Didn't process input line fully: " . join("\t", @$line), "warning";
                                                }

                                                # Add the initial inputs to the first protocol.
                                                foreach my $input (@extra_inputs) {
                                                  # Totally ignoring direction here because initial data can be
                                                  # "outputs" from an invisible-to-us prior process
                                                  $protocols[0]->add_input_datum($input->{'datum'});
                                                }

                                                # Return the protocols
                                                return \@protocols;
                                              },
                                              scalar(@{$item[2]})
                                            ];
                                          } else {
                                            $return = 0;
                                          }
                                        }
                                        | <error>

    end_of_line:                        <skip:'[" \t\n\r]*'> /\Z/

    ## # # # # # # # # # # # # ##
    # PROTOCOL                  #
    ## # # # # # # # # # # # # ##
    protocol_ref:                       /Protocol *REF/i

    protocol:                           protocol_ref term_source(?) attribute(s?) input_or_output(s?)
                                        { 
                                          $return = sub {
                                            my ($self, $values) = @_;
                                            my $value = shift(@$values);
                                            return $self->create_protocol($value, $item[2], $item[3], $item[4], $values);
                                          };
                                        }

    ## # # # # # # # # # # # # ##
    # INPUT/OUTPUT GENERIC      #
    ## # # # # # # # # # # # # ##
    input_or_output:                    input | output

    input:                              parameter
                                          { $return = sub { return { 'direction' => 'input', 'datum' => &{$item[1]}(@_) } } }
                                        | parameter_file
                                          { $return = sub { return { 'direction' => 'input', 'datum' => &{$item[1]}(@_) } } }
                                        | array_design_ref
                                          { $return = sub { return { 'direction' => 'input', 'datum' => &{$item[1]}(@_) } } }
                                        | hybridization_name
                                          { $return = sub { return { 'direction' => 'input', 'datum' => &{$item[1]}(@_) } } }

    output:                             result 
                                          { $return = sub { return { 'direction' => 'output', 'datum' => &{$item[1]}(@_) } } }
                                        | array_data_file 
                                          { $return = sub { return { 'direction' => 'output', 'datum' => &{$item[1]}(@_) } } }
                                        | biomaterial
                                          { $return = sub { return { 'direction' => 'output', 'datum' => &{$item[1]}(@_) } } }
                                        | data_file 
                                          { $return = sub { return { 'direction' => 'output', 'datum' => &{$item[1]}(@_) } } }
                                        | array_matrix_data_file
                                          { $return = sub { return { 'direction' => 'output', 'datum' => &{$item[1]}(@_) } } }

    ## # # # # # # # # # # # # ##
    # INPUT TYPES               #
    ## # # # # # # # # # # # # ##
    parameter_heading:                  /Parameter *Values?/i
    parameter:                          parameter_heading <skip:' *'> bracket_term <skip:' *'> paren_term(?) <skip:'[ "]*\t[ "]*'> term_source(?) attribute(s?)
                                        { 
                                          $return = sub {
                                            my ($self, $values) = @_;
                                            my $value = shift(@$values);
                                            my $type = $item[5][0] || undef;
                                            return $self->create_datum($item[1], $value, $item[3], $type, $item[7], $item[8], $values);
                                          };
                                        }

    parameter_file_header:              /Parameter *Files?/i
    parameter_file:                     parameter_file_header <skip:' *'> bracket_term <skip:' *'> paren_term(?) <skip:'[ "]*\t[ "]*'> attribute(s?)
                                        { 
                                          $return = sub {
                                            my ($self, $values) = @_;
                                            my $value = shift(@$values);
                                            my $type = $item[5][0] || 'modtab:file';
                                            return $self->create_datum($item[1], $value, $item[3], $type, undef, $item[7], $values);
                                          };
                                        }

    array_design_ref_heading:           /Array *Design *REF/i
    array_design_ref:                   array_design_ref_heading <skip:' *'> bracket_term <skip:' *'> paren_term(?) <skip:'[ "]*\t[ "]*'> term_source(?) attribute(s?)
                                        { 
                                          $return = sub {
                                            my ($self, $values) = @_;
                                            my $value = shift(@$values);
                                            my $type = $item[5][0] || undef;
                                            return $self->create_datum($item[1], $value, $item[3], $type, $item[7], $item[8], $values);
                                          };
                                        }

    hybridization_name_heading:         /Hybridi[sz]ation *Names?/i
    hybridization_name:                 hybridization_name_heading <skip:' *'> bracket_term(?) <skip:' *'> paren_term(?) <skip:'[ "]*\t[ "]*'> term_source(?) attribute(s?)
                                        { 
                                          $return = sub {
                                            my ($self, $values) = @_;
                                            my $value = shift(@$values);
                                            my $type = $item[5][0] || undef;
                                            return $self->create_datum($item[1], $value, $item[3][0], $type, $item[7], $item[8], $values);
                                          };
                                        }



    ## # # # # # # # # # # # # ##
    # OUTPUT TYPES              #
    ## # # # # # # # # # # # # ##
    result_header:                      /Result *Values?/i
    result:                             result_header <skip:' *'> bracket_term <skip:' *'> paren_term(?) <skip:'[ "]*\t[ "]*'> term_source(?) attribute(s?)
                                        { 
                                          $return = sub {
                                            my ($self, $values) = @_;
                                            my $value = shift(@$values);
                                            my $type = $item[5][0] || undef;
                                            return $self->create_datum($item[1], $value, $item[3], $type, $item[7], $item[8], $values);
                                          };
                                        }

    biomaterial:                        source_name | sample_name | extract_name | labeled_extract_name

    source_name_heading:                /Source *Names?/i 
    source_name:                        source_name_heading <skip:' *'> paren_term(?) <skip:'[ "]*\t[ "]*'> term_source(?) attribute(s?)
                                        { 
                                          $return = sub {
                                            my ($self, $values) = @_;
                                            my $value = shift(@$values);
                                            my $type = $item[3][0] || 'mage:biosource';
                                            return $self->create_datum($item[1], $value, undef, $type, $item[5], $item[6], $values);
                                          };
                                        }

    sample_name_heading:                /Sample *Names?/i
    sample_name:                        sample_name_heading <skip:' *'> paren_term(?) <skip:'[ "]*\t[ "]*'> term_source(?) attribute(s?)
                                        { 
                                          $return = sub {
                                            my ($self, $values) = @_;
                                            my $value = shift(@$values);
                                            my $type = $item[3][0] || 'mage:biosample';
                                            return $self->create_datum($item[1], $value, undef, $type, $item[3], $item[4], $values);
                                          };
                                        }

    extract_name_heading:               /Extract *Names?/i
    extract_name:                       extract_name_heading <skip:' *'> paren_term(?) <skip:'[ "]*\t[ "]*'> term_source(?) attribute(s?)
                                        { 
                                          $return = sub {
                                            my ($self, $values) = @_;
                                            my $value = shift(@$values);
                                            my $type = $item[3][0] || 'mage:biosample';
                                            return $self->create_datum($item[1], $value, undef, $type, $item[5], $item[6], $values);
                                          };
                                        }

    labeled_extract_name_heading:       /Labell?ed *Extract *Names?/i
    labeled_extract_name:               labeled_extract_name_heading <skip:' *'> paren_term(?) <skip:'[ "]*\t[ "]*'> term_source(?) attribute(s?)
                                        { 
                                          $return = sub {
                                            my ($self, $values) = @_;
                                            my $value = shift(@$values);
                                            my $type = $item[3][0] || 'mage:labeledextract';
                                            return $self->create_datum($item[1], $value, undef, $type, $item[5], $item[6], $values);
                                          };
                                        }


    data_file_header:                   /Result *Files?/i
    data_file:                          data_file_header <skip:' *'> bracket_term <skip:' *'> paren_term(?) <skip:'[ "]*\t[ "]*'> attribute(s?)
                                        { 
                                          $return = sub {
                                            my ($self, $values) = @_;
                                            my $value = shift(@$values);
                                            my $type = $item[5][0] || 'modtab:generic_file';
                                            return $self->create_datum($item[1], $value, $item[3], $type, undef, $item[7], $values);
                                          };
                                        }

    array_data_file_header:             /(Derived)? *Array *Data *Files?/i
    array_data_file:                    array_data_file_header <skip:' *'> bracket_term <skip:' *'> paren_term(?) <skip:'[ "]*\t[ "]*'> attribute(s?)
                                        { 
                                          $return = sub {
                                            my ($self, $values) = @_;
                                            my $value = shift(@$values);
                                            my $type = $item[5][0] || 'mage:datafile';
                                            return $self->create_datum($item[1], $value, $item[3], $type, undef, $item[7], $values);
                                          };
                                        }

    array_matrix_data_file_header:      /Array *Matrix *Data *Files?/i
    array_matrix_data_file:             array_matrix_data_file_header <skip:' *'> bracket_term  <skip:' *'> paren_term(?) <skip:'[ "]*\t[ "]*'> attribute(s?)
                                        { 
                                          $return = sub {
                                            my ($self, $values) = @_;
                                            my $value = shift(@$values);
                                            my $type = $item[5][0] || 'mage:datafile';
                                            return $self->create_datum($item[1], $value, $item[3], $type, undef, $item[7], $values);
                                          };
                                        }


    ## # # # # # # # # # # # # ##
    # OTHER METADATA            #
    ## # # # # # # # # # # # # ##
    attribute:                          attribute_text <skip:' *'> bracket_term(?) <skip:' *'> paren_term(?) <skip:'[ "]*\t[ "]*'> term_source(?)
                                        { 
                                          $return = sub {
                                            my ($self, $values) = @_;
                                            my $value = shift(@$values);
                                            return $self->create_attribute($value, $item[1], $item[3][0], $item[5][0], $item[7], $values);
                                          };
                                        }

    attribute_text:                     ...!input ...!output ...!protocol 
                                        ...!term_accession_number ...!term_source 
                                        ...!parameter_file_header ...!data_file_header
                                        /([^\t"\[\(]+)[ "]*/
                                        { 
                                          $return = $1;
                                          $return =~ s/^\s*|\s*[\r\n]+//g;
                                        }

    term_source_header:                 /Term *Source *REF/i
                                        {
                                          $return = sub {
                                            my ($self, $values) = @_;
                                            my $value = shift(@$values);
                                            return $value;
                                          };
                                        }
    term_accession_number:              /Term *Accession *(?:Numbers?)?/i
                                        {
                                          $return = sub {
                                            my ($self, $values) = @_;
                                            my $value = shift(@$values);
                                            return $value;
                                          };
                                        }
    term_source:                        term_source_header term_accession_number(?)
                                        {
                                          $return = sub {
                                            my ($self, $values) = @_;
                                            return $self->create_termsource($item[1], $item[2], $values);
                                          };
                                        }

    bracket_term:                       /\A \[ [ ]* ([^\]]+?) [ ]* \]/xms
                                        { $return = $1 }
    paren_term:                         /\A \( [ ]* ([^\)]+?) [ ]* \)/xms
                                        { $return = $1 }


  GRAMMAR

}
sub parse {
  my ($self, $document) = @_;
  if ( -r $document ) {
    local $/;
    unless(open FH, "<$document") {
      log_error "Couldn't read SDRF file $document.";
      return 0;
    }
    $document = <FH>;
    close FH;
  } else {
    log_error "Can't find SDRF file $document.";
    return 0;
  }
  $document =~ s/\A [" ]*/\t/gxms;
  $document =~ s/\015(?![\012])/\n/g; # Replace old-style (thanks, Excel) Mac CR endings with LFs
  my $parser = $self->_get_parser();
  open DOC, '<', \$document;

  # Parse header line
  my $header = <DOC>;
  my $parse_results = $parser->SDRF_header($header);
  if (!$parse_results) { 
    log_error "Couldn't parse header line of SDRF.";
    return 0;
  }
  my ($row_parser, $num_applied_protocols) = @$parse_results;

  my @applied_protocol_slots;
  for (my $i = 0; $i < $num_applied_protocols; $i++) {
    $applied_protocol_slots[$i] = [];
  }

  # Parse the rest of the file
  while (my $line = <DOC>) {
    $line =~ s/[\r\n]*$//g;
    next if $line =~ m/^\s*#/; # Skip comments
    next if $line =~ m/^\s*$/; # Skip blank lines

    # Parse and build objects for this row
    my @vals = split /\t/, $line;
    @vals = map { s/^"|"$//g; $_; } @vals;
    my $applied_protocols = &{$row_parser}($self, \@vals);

    # Sanity check
    if (scalar(@$applied_protocols) != $num_applied_protocols) {
      log_error "Got back " . scalar(@$applied_protocols) . " applied_protocols when $num_applied_protocols applied_protocols were expected.";
      return 0;
    }

    my $applied_protocol_slot = 0;
    for (my $applied_protocol_slot = 0; $applied_protocol_slot < $num_applied_protocols; $applied_protocol_slot++) {
      push(@{$applied_protocol_slots[$applied_protocol_slot]}, $applied_protocols->[$applied_protocol_slot]);
    }
  }

  # Okay, we've got a bunch of rows of data.

  # Need a little post-processing: make outputs of previous applied_protocols be 
  # inputs to following applied_protocols.
  my $anonymous_data_num = 0;
  for (my $i = 0; $i < $num_applied_protocols-1; $i++) {
    for (my $j = 0; $j < scalar(@{$applied_protocol_slots[$i]}); $j++) {
      my $previous_applied_protocol = $applied_protocol_slots[$i][$j];
      my $next_applied_protocol = $applied_protocol_slots[$i+1][$j];
      my $data = $previous_applied_protocol->get_output_data();
      if (scalar(@$data)) {
        foreach my $datum (@$data) {
          $next_applied_protocol->add_input_datum($datum);
        }
      }
    }
  }
  my @anonymous_data_by_applied_protocol; # = [ { 'anonymous_datum' => datum, 'applied_protocol' => previous_applied_protocol }  ]
  for (my $i = 0; $i < $num_applied_protocols-1; $i++) {
    for (my $j = 0; $j < scalar(@{$applied_protocol_slots[$i]}); $j++) {
      my $previous_applied_protocol = $applied_protocol_slots[$i][$j];
      my $next_applied_protocol = $applied_protocol_slots[$i+1][$j];
      my $data = $previous_applied_protocol->get_output_data();
      if (!scalar(@$data)) {
        # No outputs, so we need to create an anonymous link
        grep { $previous_applied_protocol->equals($_->{'applied_protocol'}) } @anonymous_data_by_applied_protocol;
        my ($existing_anonymous_datum) = map { $_->{'anonymous_datum'} } grep { $previous_applied_protocol->equals($_->{'applied_protocol'}) } @anonymous_data_by_applied_protocol;
        # Don't create a new anonymous datum if it's to be the output of an identical previous protocol
        if (!$existing_anonymous_datum) {
          my $type = new ModENCODE::Chado::CVTerm({
              'name' => 'anonymous_datum',
              'cv' => new ModENCODE::Chado::CV({
                  'name' => 'modencode'
                }),
            });
          my $anonymous_datum = new ModENCODE::Chado::Data({
              'heading' => "Anonymous Datum #" . $anonymous_data_num++,
              'type' => $type,
              'anonymous' => 1,
            });
          push @anonymous_data_by_applied_protocol, { 'anonymous_datum' => $anonymous_datum, 'applied_protocol' => $previous_applied_protocol->clone() };
          $previous_applied_protocol->add_output_datum($anonymous_datum);
          $next_applied_protocol->add_input_datum($anonymous_datum);
        } else {
          $previous_applied_protocol->add_output_datum($existing_anonymous_datum);
          $next_applied_protocol->add_input_datum($existing_anonymous_datum);
        }
      }
    }
  }

  for (my $i = 0; $i < $num_applied_protocols; $i++) {
    $applied_protocol_slots[$i] = $self->_reduce_applied_protocols($applied_protocol_slots[$i]);
  }

  my $experiment = new ModENCODE::Chado::Experiment({
      'applied_protocol_slots' => \@applied_protocol_slots,
    });

  return $experiment;
}

sub _reduce_applied_protocols : PRIVATE {
  my ($self, $applied_protocols) = @_;
  my @merged_applied_protocols;
  foreach my $applied_protocol (@$applied_protocols) {
    if (!scalar(grep { $_->equals($applied_protocol) } @merged_applied_protocols)) {
      push @merged_applied_protocols, $applied_protocol;
    }
  }
  return \@merged_applied_protocols;
}

sub _get_parser : RESTRICTED {
  my ($self) = @_;
  $::RD_ERRORS++;
  $::RD_WARN++;
  $::RD_HINT++;
  $Parse::RecDescent::skip = '[ "]*\t[ "]*';
  my $parser = new Parse::RecDescent($grammar{ident $self});
}

sub create_datum {
  my ($self, $heading, $value, $name, $type, $termsource, $attributes, $values) = @_;

  my $datum = new ModENCODE::Chado::Data({
      'name' => $name,
      'heading' => $heading,
      'value' => $value,
    });

  # Map functions to values; order matters (should match datums)
  my ($termsource) = map { &$_($self, $values) } @$termsource;
  my @attributes = map { &$_($self, $values) } @$attributes;

  # Term source
  if ($termsource) {
    $datum->set_termsource($termsource);
  }

  # Attributes
  foreach my $attribute (@attributes) {
    $datum->add_attribute($attribute);
  }

  # Type
  if ($type) {
    my ($cv, $cvterm) = split(/:/, $type, 2);
    $type = new ModENCODE::Chado::CVTerm({
        'name' => $cvterm,
        'cv' => new ModENCODE::Chado::CV({
            'name' => $cv,
          }),
      });
    $datum->set_type($type);
  }

  return $datum;
}

sub create_protocol {
  my ($self, $name, $termsource, $attributes, $data, $values) = @_;
  my $protocol = new ModENCODE::Chado::Protocol({
      'name'       => $name,
    });

  # Map functions to values; order matters (should match inputs)
  my ($termsource) = map { &$_($self, $values) } @$termsource;
  my @attributes = map { &$_($self, $values) } @$attributes;
  my @data = map { &$_($self, $values) } @$data;

  # Term source
  if ($termsource) {
    $protocol->set_termsource($termsource);
  }

  # Attributes
  foreach my $attribute (@attributes) {
    $protocol->add_attribute($attribute);
  }

  my $applied_protocol = new ModENCODE::Chado::AppliedProtocol({
      'protocol'       => $protocol,
    });

  # Input/Output data
  foreach my $datum (@data) {
    if ($datum->{'direction'} eq 'input') {
      $applied_protocol->add_input_datum($datum->{'datum'});
    }
  }
  foreach my $datum (@data) {
    if ($datum->{'direction'} eq 'output') {
      $applied_protocol->add_output_datum($datum->{'datum'});
    }
  }
  return $applied_protocol;
}

sub create_termsource {
  my ($self, $termsource_ref, $accession, $values) = @_;
  $termsource_ref = &$termsource_ref($self, $values);
  return undef unless length($termsource_ref);
  ($accession) = map { &$_($self, $values) } @$accession;
  my $db = new ModENCODE::Chado::DB({
      'name' => $termsource_ref,
    });
  my $dbxref = new ModENCODE::Chado::DBXref({
      'db' => $db,
    });
  if (length($accession)) {
    $dbxref->set_accession($accession);
  }
  return $dbxref;
}

sub create_attribute {
  my ($self, $value, $heading, $name, $type, $termsource, $values) = @_;
  my $attribute = new ModENCODE::Chado::Attribute({
      'heading' => $heading,
      'name' => $name,
      'value' => $value,
    });

  # Map functions to values; order matters (should match inputs)
  my ($termsource) = map { &$_($self, $values) } @$termsource;

  # Type
  if ($type) {
    my ($cv, $cvterm) = split(/:/, $type, 2);
    $type = new ModENCODE::Chado::CVTerm({
        'name' => $cvterm,
        'cv' => new ModENCODE::Chado::CV({
            'name' => $cv,
          }),
      });
    $attribute->set_type($type);
  } else {
    $type = new ModENCODE::Chado::CVTerm({
        'name' => 'string',
        'cv' => new ModENCODE::Chado::CV({
            'name' => 'xsd',
          }),
      });
    $attribute->set_type($type);
  }

  # Term source
  if ($termsource) {
    $attribute->set_termsource($termsource);
  }

  return $attribute;
}

1;
