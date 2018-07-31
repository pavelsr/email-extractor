#ABSTRACT: Set of functions that can be useful when building web crawlers

=head1 NAME

Email::Extractor::Utils

=head1 DESCRIPTION

Set of useful utilities that works with html and urls

=head1 SYNOPSIS

  use Email::Extractor::Utils qw( looks_like_url looks_like_file get_file_uri load_addr_to_str )
  # or use Email::Extractor::Utils qw[:ALL];
  Email::Extractor::Utils::Verbose = 1;
  
  my $text = load_addr_to_str($url);

=cut

package Email::Extractor::Utils;

use strict;
use warnings;
use feature 'say';

use Cwd;
use Carp;
use URI::URL;
use File::Spec;
use File::Slurp qw(read_file);
use File::Basename;  # fileparse
use Regexp::Common qw /URI/;
use LWP::UserAgent;
use Mojo::DOM;

require Exporter;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    looks_like_url 
    looks_like_rel_link
    looks_like_file 
    get_file_uri 
    load_addr_to_str
    absolutize_links_array
    find_all_links
    find_links_by_text
    drop_asset_links
    drop_anchor_links
    remove_query_params
    remove_external_links
);
our %EXPORT_TAGS = ( 'ALL' => [ @EXPORT_OK ] );

our $Verbose = 0 unless defined $Verbose;

=head2 $Email::Extractor::Utils::Assets

List of asset extensions, used in L<Email::Extractor::Utils/drop_asset_links>

To see default list of assets:

    perl -Ilib -E "use Email::Extractor::Utils qw(:ALL); use Data::Dumper; print Dumper $Email::Extractor::Utils::Assets;"

=cut

our $Assets = [
    'css', 
    'less', 
    'js', 
    'jpg', 
    'JPG', 
    'jpeg', 
    'JPEG', 
    'png', 
    'PNG', 
    'svg', 
    'doc', 
    'docx', 
    'ppt', 
    'odt', 
    'rtf', 
    'ppt'
];

=head2 load_addr_to_str

Accept URI of file path and return string with content

    my $text = load_addr_to_str($url);
    my $text = load_addr_to_str($path_to_file);

Function can accept http(s) uri or file paths both

dies if no such file

return $resp->content even if no such url

Can be used in tests when you need to mock http requests also

=cut

sub load_addr_to_str {
    my $addr = shift;

    eval {
        
        if ( looks_like_url($addr) ) {
            
            say "$addr: is url" if ($Verbose);
            my $ua = LWP::UserAgent->new;
            my $resp = $ua->get($addr);             # HTTP::Response
            return $resp->content;
            
        } else {
            
            say "$addr: is file" if ($Verbose);
            my $file_uri = get_file_uri($addr);
            
            if ( looks_like_file($file_uri) ) {
                return read_file( get_abs_path($addr) );
        
            } else {
                die "No such file: ".$addr." or it is not file or http uri";
            }
            
        }
        
    }
}

=head2 get_abs_path

Return absolute path of file relative to current working directory

=cut

sub get_abs_path {
    my $filename = shift;
    return File::Spec->catfile(getcwd(), $filename);
}

=head2 get_file_uri

Make absolute path from relative (to cwd) and return absolute path that can pass L<Regexp::Common::URI::file> validation

    get_file_uri('/test')   # 'file:///root/test' if cwd is /root

=cut

sub get_file_uri {
    my $filename = shift;
    return 'file://'.File::Spec->catfile(getcwd(), $filename);
}


=head2 looks_like_url

    looks_like_url('http://example.com')      # 1
    looks_like_url('https://example.com')      # 1
    looks_like_url('/root/somefolder')        # 0

Detect if link is http or https url

Uses L<Regexp::Common::URI::http>

Return: 

O if provided string is not url

url without query, L<https://metacpan.org/pod/Regexp::Common::URI::http#$7> if provided string is url

=cut

sub looks_like_url {
    my $string = shift;
    my $regexp = qr($RE{URI}{HTTP}{-scheme=>qr/https?/}{-keep});
    if ( $string =~ $regexp ) {
        # warn "$1 $2 $3 $4 $5 $6 $7 $8";
        return $7 if defined $7;
        return $1 if defined $1;
    } else {
        return 0;
    }
}


=head2 looks_like_rel_link

    Return true if link looks like relative url, either return false

=cut

sub looks_like_rel_link {
    my $link = shift;
    return 0 if ( looks_like_url($link) );
    return 1;
}

=head2 looks_like_file

    looks_like_file('http://example.com')             # 0
    looks_like_file('file:///root/somefolder')        # 1

Detect if string is file uri or no

Uses L<Regexp::Common::URI::file>

=cut

sub looks_like_file {
    my $string = shift;
    if ( $string =~ qr($RE{URI}{file}) ) {
        return 1;
    } else {
        return 0;
    }
}

=head2 absolutize_links_array

Make all links in array absolute

    my $res = absolutize_links( $links, 'http://example.com ');
    
C<$links> must be C<ARRAYREF>, return also C<ARRAYREF>

=cut

sub absolutize_links_array {
    my ($links_arr, $dname) = @_;
    
    confess 'No valid dname in absolutize_links_array()' unless defined $dname && length $dname;
    
    my @res;
    
    for my $l (@$links_arr) {
        if ( looks_like_rel_link($l) ) {
            $l = url($l, $dname)->abs->as_string;
        }
        push @res, $l;
    }
    
    return \@res;
}


=head2 remove_external_links

    my $res = absolutize_links( $links, 'http://example.com ');  # leave only links on http://example.com
    
Relative links stay untouched

C<$links> must be C<ARRAYREF>, return also C<ARRAYREF>

=cut

sub remove_external_links {
    my ($links_arr, $only_dname) = @_;
    
    confess 'No valid dname in remove_external_links()' unless defined $only_dname && length $only_dname;
    
    my @res = grep { ( $_ =~ /^$only_dname/ ) || looks_like_file('file://'.$_) } @$links_arr;
    # looks_like_file('file://'.$_) = looks_like_relative_link
    return \@res;
}


=head2 drop_asset_links 

    my $res = drop_asset_links($links)

Leave only links that are not related to assets. Remove query params also

C<$links> must be C<ARRAYREF>, return also C<ARRAYREF>

=cut


sub drop_asset_links {
    my $links = shift;
    
    $links = remove_query_params($links);
    
    my @res;
    
    for my $link (@$links) {
        my($filename, $dirs, $suffix) = fileparse($link, @$Assets);
        push (@res, $link) if ($suffix eq '');
    }
    
    return \@res;
}


=head2 drop_anchor_links 

    my $res = drop_anchor_links ($links)

Leave only links that are not anchors to same page (anchor link is like C<#rec31047364>)

C<$links> must be C<ARRAYREF>, return also C<ARRAYREF>

=cut

sub drop_anchor_links {
    my $links_arr = shift;
    my @res = grep { $_ !~ /^#/ } @$links_arr;
    return \@res;
}


=head2 remove_query_params

Remove GET query params from provided links array

    my $res = remove_query_params($links)

C<$links> must be C<ARRAYREF>, return also C<ARRAYREF>

=cut

sub remove_query_params {
    my $links = shift;
    
    my @res;
    
    for my $link (@$links) {
        my $uri = URI->new($link);
        if ($uri->query) {
            my $l = length($link) - length($uri->query) - 1;
            my $new_str = substr $link, 0, $l;
            push (@res, $new_str);
        } else {
            push (@res, $link);
        }
    }
    
    return \@res;
}

=head2 find_all_links

Find all links and return href attributes of C<a> tags

Return C<ARRAYREF>

=cut

sub find_all_links {
    my $html = shift;
    my $dom = Mojo::DOM->new($html);    
    return $dom->find('a')->map(attr => 'href')->to_array;
}

=head2 find_links_by_text

Find all C<a> tags containing particular text and return href values

If no search text specified return all links

Currently is not used in L<Email::Extractor> project since it has unexpected behaviour (see tests) 

Return C<ARRAYREF>

TO-DO: try to implement this method with L<HTML::LinkExtor>

=cut

sub find_links_by_text {
    my ($html, $a_text) = @_;
    my $dom = Mojo::DOM->new($html);
    # Mojo::Collection of Mojo::DOM
    # return $dom->find('a')->grep('text' => $a_text)->map(attr => 'href')->to_array;
    return $dom->find('a')->grep(sub { $_->text eq $a_text })->map(attr => 'href')->to_array;
}

1;
