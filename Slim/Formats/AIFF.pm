package Slim::Formats::AIFF;

# $Id$
#
# SlimServer Copyright (c) 2001-2006 Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use base qw(Slim::Formats);

use MP3::Info;
use Slim::Utils::SoundCheck;

sub getTag {
	my $class = shift;
	my $file  = shift || return {};

	my $filesize = -s $file;

	# Make sure the file exists.
	return undef unless $filesize && -r $file;

	$::d_formats && msg( "Reading AIFF information for $file\n");

	# This hash will map the keys in the tag to their values.
	#
	# Often, ID3 tags will be stored in an AIFF file. See iTunes.
	my $tags = MP3::Info::get_mp3tag($file) || {};

	my $chunkheader;

	open(my $f, $file) || return undef;

	if (read($f, $chunkheader, 12) < 12) {
		return undef;
	}

	my ($tag, $size, $format) = unpack('a4Na4', $chunkheader);
	my $chunkpos = 12;

	# size is chunk data size, without the chunk header.
	$size += 8;

	# unless told otherwise, AIFF/AIFC is big-endian
	$tags->{'ENDIAN'} = 1;
	$tags->{'FS'}     = $filesize;
	
	$::d_formats && msg("read first tag: $tag $size $format\n");
	
	if ($tag ne 'FORM' || ($format ne 'AIFF' && $format ne 'AIFC')) {
		return undef;
	}

	if ($::d_formats && $size != $filesize) {

		# iTunes rips with bogus size info...
		msg("AIFF::getTag: ignores invalid filesize in header = $size, actual file size = $filesize\n");
	}

	my %readchunks = ();

	while ($chunkpos < $filesize) {

		if (!seek($f, $chunkpos, 0)) {
			return undef;
		}

		if (read($f, $chunkheader, 8) < 8) {
			return undef;
		}

		($tag, $size) = unpack "a4N", $chunkheader;

		$readchunks{$tag} = 1;

		$::d_formats && msg("read tag: $tag $size at file offset $chunkpos\n");

		# look for the sound chunk
		if ($tag eq 'SSND') {

			my $ssndheader;

			if (read($f, $ssndheader, 8) < 8) {
				return undef;
			}

 			my ($dataoffset, $blocksize) = unpack('NN', $ssndheader);

  			# ignore the blocksize for now...
 			$tags->{'OFFSET'} = $chunkpos + 16 + $dataoffset;

		# look for the chunk describing the format
		} elsif ($tag eq 'COMM') {

			my $expectedsize = $format eq 'AIFF' ? 18 : 22;
			my $commheader   = undef;

			if ($size < $expectedsize) {
				return undef;
			}

 			if (read($f, $commheader, $expectedsize) != $expectedsize) {
				return undef;
			}

 			my ($numChannels, $numSampleFrames, $sampleSize, $sampleRateExp, $sampleRateMantissa, $encoding) 
				= unpack('nNnxCNxxxxa4', $commheader);

 			$tags->{'CHANNELS'}   = $numChannels;
 			$tags->{'SAMPLESIZE'} = $sampleSize;
 			$tags->{'SIZE'}       = $numSampleFrames * $numChannels * $sampleSize / 8;

 			# calculate the sample rate (as an integer from the 80 bit IEEE floating point value, given the exponent and mantissa
    			$sampleRateExp = 30 - $sampleRateExp;

    			my $lastMantissa;

			while ($sampleRateExp--) {

 				$lastMantissa = $sampleRateMantissa;
 			 	$sampleRateMantissa = $sampleRateMantissa >> 1;
 		   	}

 		   	if ($lastMantissa & 0x00000001) {

 		   		$sampleRateMantissa++;
			}

 			my $samplesPerSecond = $sampleRateMantissa;

 			if ($samplesPerSecond < 100 || $samplesPerSecond > 99123) {
				return undef;
			}

 		   	$tags->{'RATE'}       = $samplesPerSecond;
 		   	$tags->{'BITRATE'}    = $samplesPerSecond * $numChannels * $sampleSize;
 			$tags->{'SECS'}       = $numSampleFrames / $samplesPerSecond;
 			$tags->{'BLOCKALIGN'} = $numChannels * $sampleSize / 8;
 		   	
 		   	if ($format eq 'AIFC') {

 		   		if ($encoding eq 'sowt') {

					# little-endian 'encoding'
 		   			$tags->{'ENDIAN'} = 0;

 		   		} elsif ($encoding ne 'NONE') {

					# unable to handle compressed formats.
 					return undef;
 		   		}
 		   	}
		}

	} continue {
		$chunkpos += 8 + $size + ($size & 1);
	}

	if (!$readchunks{'COMM'}) {

		# we don't know anything about sample rates, number of channels, sample size, etc...
		# could be 8-bit mono, 16-bit stereo, ...
		$::d_formats && msg("AIFF: Missing COMM chunk\n");
		return undef;
	}

	# Look for iTunes SoundCheck data
	if ($tags->{'COMMENT'}) {

		Slim::Utils::SoundCheck::commentTagTodB($tags);
	}

	return $tags;
}

1;
