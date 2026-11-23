/// TeePod's tags, as the answer the Pod Analyser would have written.
///
/// Copyright (C) 2026, Togaware Pty Ltd.
///
/// Licensed under the GNU General Public License, Version 3 (the "License").
///
/// License: https://opensource.org/license/gpl-3-0
//
// This program is free software: you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option) any later
// version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
// details.
//
// You should have received a copy of the GNU General Public License along with
// this program. If not, see <https://opensource.org/license/gpl-3-0>.
///
/// Authors: Tony Chen

library;

import 'dart:convert';
import 'dart:math';

import 'package:photopod/services/tag_results.dart';
import 'package:photopod/services/teepod/teepod_types.dart';

// TeePod tags with the same model as the Pod Analyser, SigLIP ViT-B/16, but
// from a vocabulary of its own (teepod/demo/app/tags.txt): phrases such as
// "a beach" or "a dog", with no categories. PhotoPod names each phrase with
// a tag of its own here, in a category, using the Pod Analyser's names
// (tag_vocabulary.json in analyser/face_analyser) wherever the two mean the
// same, so that photos tagged on the web, where the Pod Analyser still does
// the work, and on the desktop, by TeePod, are filed together. That is also
// why the tags are filed under the same model, [tagModelId]: a tags file
// written under another would be thrown away by the other platform.
//
// The Pod Analyser chooses tags by how much of the whole each takes, and so
// does PhotoPod here, with its thresholds (TagConfig in its tagger.py):
// TeePod's scores, the closeness of the picture to each phrase, are turned
// into shares of one whole, sharply, as SigLIP's own scale does. TeePod is
// asked for its 50 closest phrases, of 155, so that the shares are taken of
// nearly everything: the rest lie too far away to take any.

/// How sharply closeness is turned into shares: SigLIP's own scale.

const double tagSharpness = 100;

/// The share of the whole a tag must take, and how close the picture must
/// lie to it in its own right.

const double minTagShare = 0.12;
const double minTagSimilarity = 0.035;

/// The most tags one photo is given.

const int maxTags = 4;

/// The tag and category each of TeePod's phrases is filed under. Several
/// phrases may share a tag, whose share is then theirs together. A phrase
/// mapped to null says too little to be a tag, and is passed over.

const Map<String, ({String tag, String category})?> teePodTags = {
  // People
  'a person': (tag: 'Portrait', category: 'People'),
  'a portrait': (tag: 'Portrait', category: 'People'),
  'a group of people': (tag: 'Group', category: 'People'),
  'a child': (tag: 'Children', category: 'People'),
  'a baby': (tag: 'Baby', category: 'People'),
  'a selfie': (tag: 'Selfie', category: 'People'),
  'a wedding': (tag: 'Wedding', category: 'People'),
  'a party': (tag: 'Party', category: 'People'),
  'a crowd': (tag: 'Crowd', category: 'People'),
  'a concert': (tag: 'Concert', category: 'People'),
  'sports': (tag: 'Sport', category: 'People'),
  'football': (tag: 'Football', category: 'People'),
  'basketball': (tag: 'Basketball', category: 'People'),
  'tennis': (tag: 'Tennis', category: 'People'),
  'swimming': (tag: 'Swimming', category: 'People'),
  'skiing': (tag: 'Skiing', category: 'People'),
  'surfing': (tag: 'Surfing', category: 'People'),
  'hiking': (tag: 'Hiking', category: 'People'),
  'running': (tag: 'Running', category: 'People'),
  'cycling': (tag: 'Cycling', category: 'People'),
  'camping': (tag: 'Camping', category: 'People'),

  // Animals
  'a dog': (tag: 'Dog', category: 'Animals'),
  'a cat': (tag: 'Cat', category: 'Animals'),
  'a bird': (tag: 'Bird', category: 'Animals'),
  'a horse': (tag: 'Horse', category: 'Animals'),
  'a cow': (tag: 'Farm animals', category: 'Animals'),
  'a sheep': (tag: 'Farm animals', category: 'Animals'),
  'a fish': (tag: 'Fish', category: 'Animals'),
  'an insect': (tag: 'Insect', category: 'Animals'),
  'a butterfly': (tag: 'Insect', category: 'Animals'),
  'wildlife': (tag: 'Wildlife', category: 'Animals'),

  // Nature
  'a beach': (tag: 'Beach', category: 'Nature'),
  'the ocean': (tag: 'Sea', category: 'Nature'),
  'a lake': (tag: 'Lake', category: 'Nature'),
  'a river': (tag: 'River', category: 'Nature'),
  'a waterfall': (tag: 'Waterfall', category: 'Nature'),
  'a mountain': (tag: 'Mountains', category: 'Nature'),
  'a forest': (tag: 'Forest', category: 'Nature'),
  'a tree': (tag: 'Trees', category: 'Nature'),
  'a desert': (tag: 'Desert', category: 'Nature'),
  'a field': (tag: 'Countryside', category: 'Nature'),
  'a garden': (tag: 'Garden', category: 'Nature'),
  'flowers': (tag: 'Flowers', category: 'Nature'),
  'snow': (tag: 'Snow', category: 'Nature'),
  // SigLIP cannot tell a sunrise from a sunset, and splits its share
  // between them, so they are one tag.
  'a sunset': (tag: 'Sunset', category: 'Nature'),
  'a sunrise': (tag: 'Sunset', category: 'Nature'),
  'the night sky': (tag: 'Night sky', category: 'Nature'),
  'clouds': (tag: 'Clouds', category: 'Nature'),
  'rain': (tag: 'Rain', category: 'Nature'),
  'a rainbow': (tag: 'Rainbow', category: 'Nature'),

  // Places
  'a city': (tag: 'City', category: 'Places'),
  'a skyline': (tag: 'City', category: 'Places'),
  'a street': (tag: 'Street', category: 'Places'),
  'a building': (tag: 'Architecture', category: 'Places'),
  'a house': (tag: 'Architecture', category: 'Places'),
  'a bridge': (tag: 'Bridge', category: 'Places'),
  'a church': (tag: 'Church', category: 'Places'),
  'a castle': (tag: 'Castle', category: 'Places'),
  'a monument': (tag: 'Monument', category: 'Places'),
  'a museum': (tag: 'Museum', category: 'Places'),
  'a park': (tag: 'Park', category: 'Places'),
  'a playground': (tag: 'Playground', category: 'Places'),
  'a stadium': (tag: 'Stadium', category: 'Places'),
  'an airport': (tag: 'Airport', category: 'Places'),
  'a train station': (tag: 'Railway station', category: 'Places'),
  'a shop': (tag: 'Shop', category: 'Places'),
  'a market': (tag: 'Market', category: 'Places'),
  'a restaurant': (tag: 'Restaurant', category: 'Places'),
  'a cafe': (tag: 'Café', category: 'Places'),
  'a bar': (tag: 'Bar', category: 'Places'),
  'a hotel room': (tag: 'Hotel', category: 'Places'),
  'an office': (tag: 'Office', category: 'Places'),
  'a classroom': (tag: 'Classroom', category: 'Places'),
  'a kitchen': (tag: 'Kitchen', category: 'Places'),
  'a living room': (tag: 'Home', category: 'Places'),
  'a bedroom': (tag: 'Home', category: 'Places'),
  'a bathroom': (tag: 'Home', category: 'Places'),

  // Food and drink
  'food': (tag: 'Food', category: 'Food and drink'),
  'a meal': (tag: 'Food', category: 'Food and drink'),
  'a cake': (tag: 'Cake', category: 'Food and drink'),
  'dessert': (tag: 'Dessert', category: 'Food and drink'),
  'fruit': (tag: 'Fruit', category: 'Food and drink'),
  'vegetables': (tag: 'Vegetables', category: 'Food and drink'),
  'pizza': (tag: 'Pizza', category: 'Food and drink'),
  'a burger': (tag: 'Burger', category: 'Food and drink'),
  'sushi': (tag: 'Sushi', category: 'Food and drink'),
  'bread': (tag: 'Bread', category: 'Food and drink'),
  'coffee': (tag: 'Coffee', category: 'Food and drink'),
  'wine': (tag: 'Drinks', category: 'Food and drink'),
  'beer': (tag: 'Drinks', category: 'Food and drink'),
  'a cocktail': (tag: 'Drinks', category: 'Food and drink'),

  // Things
  'a car': (tag: 'Car', category: 'Things'),
  'a bus': (tag: 'Bus', category: 'Things'),
  'a truck': (tag: 'Lorry', category: 'Things'),
  'a motorcycle': (tag: 'Motorbike', category: 'Things'),
  'a bicycle': (tag: 'Bicycle', category: 'Things'),
  'a train': (tag: 'Train', category: 'Things'),
  'an airplane': (tag: 'Aeroplane', category: 'Things'),
  'a boat': (tag: 'Boat', category: 'Things'),
  'a ship': (tag: 'Boat', category: 'Things'),
  'a computer': (tag: 'Computer', category: 'Things'),
  'a phone': (tag: 'Phone', category: 'Things'),
  'a television': (tag: 'Television', category: 'Things'),
  'a camera': (tag: 'Camera', category: 'Things'),
  'a book': (tag: 'Books', category: 'Things'),
  'a painting': (tag: 'Art', category: 'Things'),
  'a drawing': (tag: 'Art', category: 'Things'),
  'a toy': (tag: 'Toys', category: 'Things'),
  'a musical instrument': (tag: 'Musical instrument', category: 'Things'),
  'a guitar': (tag: 'Guitar', category: 'Things'),
  'a piano': (tag: 'Piano', category: 'Things'),
  'furniture': (tag: 'Furniture', category: 'Things'),
  'clothing': (tag: 'Clothing', category: 'Things'),
  'shoes': (tag: 'Shoes', category: 'Things'),
  'jewelry': (tag: 'Jewellery', category: 'Things'),
  'a bag': (tag: 'Bag', category: 'Things'),

  // Occasions
  'a festival': (tag: 'Festival', category: 'Occasions'),
  'fireworks': (tag: 'Fireworks', category: 'Occasions'),
  'a birthday party': (tag: 'Birthday', category: 'Occasions'),
  'christmas': (tag: 'Christmas', category: 'Occasions'),
  'a graduation': (tag: 'Graduation', category: 'Occasions'),

  // Documents
  'a screenshot': (tag: 'Screenshot', category: 'Documents'),
  'a document': (tag: 'Document', category: 'Documents'),
  'text': (tag: 'Document', category: 'Documents'),
  'a receipt': (tag: 'Receipt', category: 'Documents'),
  'a whiteboard': (tag: 'Whiteboard', category: 'Documents'),
  'a diagram': (tag: 'Diagram', category: 'Documents'),
  'a map': (tag: 'Map', category: 'Documents'),
  'a meme': (tag: 'Meme', category: 'Documents'),

  // Photo style
  'a black and white photo': (tag: 'Black and white', category: 'Photo style'),
  'an underwater photo': (tag: 'Underwater', category: 'Photo style'),
  'an aerial photo': (tag: 'Aerial', category: 'Photo style'),

  // Fitting almost any photo of a person, or of a holiday, these take a
  // large share from the tags that say something.
  'a close-up photo': null,
  'travel': null,
};

/// The tag and category for [phrase]: its own from [teePodTags], or, for a
/// phrase TeePod has gained since, the phrase itself without its article,
/// under Other.

({String tag, String category})? tagForPhrase(String phrase) {
  if (teePodTags.containsKey(phrase)) return teePodTags[phrase];
  final words = phrase.trim().replaceFirst(RegExp(r'^(a|an|the)\s+'), '');
  if (words.isEmpty) return null;
  return (tag: words[0].toUpperCase() + words.substring(1), category: 'Other');
}

/// The tags PhotoPod gives a photo TeePod scored as [scores], best first.

List<FoundTag> chooseTags(List<TeePodTag> scores) {
  if (scores.isEmpty) return const [];
  final best = scores.map((t) => t.score).reduce(max);
  final weights = [
    for (final t in scores) exp(tagSharpness * (t.score - best)),
  ];
  final whole = weights.fold<double>(0, (sum, w) => sum + w);

  final shares = <String, ({String category, double share, double close})>{};
  for (var i = 0; i < scores.length; i++) {
    final named = tagForPhrase(scores[i].name);
    if (named == null) continue;
    final had = shares[named.tag];
    shares[named.tag] = (
      category: had?.category ?? named.category,
      share: (had?.share ?? 0) + weights[i] / whole,
      close: max(had?.close ?? double.negativeInfinity, scores[i].score),
    );
  }

  final ranked = shares.entries.toList()
    ..sort((a, b) => b.value.share.compareTo(a.value.share));
  final chosen = <FoundTag>[];
  for (final MapEntry(key: tag, value: v) in ranked.take(maxTags)) {
    if (v.share < minTagShare || v.close < minTagSimilarity) break;
    chosen.add((
      tag: tag,
      category: v.category,
      score: (v.share * 1000).round() / 1000,
    ));
  }
  return chosen;
}

/// [answer], TeePod's tags for a photo, as the JSON the Pod Analyser writes
/// in the tag inbox, which `TagResult.parse` reads.

String tagAnswerFromTeePod(TeePodAnswer answer) {
  final result = <String, Object?>{
    'format': 'photopod-tag-result',
    'version': 1,
    'model': tagModelId,
    'analysed': DateTime.now().toUtc().toIso8601String(),
    'analyser': 'teepod',
  };
  if (answer.error != null) {
    return jsonEncode(result..['failed'] = answer.error);
  }
  return jsonEncode(
    result..['tags'] = foundTagsToJson(chooseTags(answer.tags)),
  );
}
