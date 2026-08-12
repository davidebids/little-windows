#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"

NUTRIENT_IDS = {
  energy: [1008, 2047, 2048],
  protein: [1003],
  fat: [1004],
  fiber: [1079],
  iron: [1089],
  zinc: [1095],
  calcium: [1087],
  vitamin_c: [1162]
}.freeze

CATEGORY_NAMES = %w[
  fruit vegetable grain plantProtein meat seafood dairy egg nutAndSeed
  herbAndFlavor preparedFood
].freeze

# These records are preferred over text matching when FoodData Central has a
# clear preparation-specific record whose description does not mirror the app
# label closely enough for the matcher to select it reliably.
FDC_ID_OVERRIDES = {
  "apple" => "171688",
  "applesauce" => "171695",
  "avocado" => "171705",
  "banana" => "173944",
  "black-bean" => "173735",
  "boysenberry" => "171713",
  "broccoli" => "169967",
  "broccoli-rabe" => "170382",
  "butternut-squash" => "169296",
  "carrot" => "170394",
  "coconut-flesh" => "170169",
  "collard-greens" => "170407",
  "green-cabbage" => "2709889",
  "napa-cabbage" => "169980",
  "purple-cabbage" => "169978",
  "snap-pea" => "170011",
  "star-fruit" => "171715",
  "water-chestnut" => "170066",
  "yellow-squash" => "2709991",
  "bread" => "172686",
  "brown-rice" => "169704",
  "toast" => "172687",
  "whole-wheat-bread" => "2707709",
  "whole-wheat-toast" => "172689",
  "infant-barley-cereal" => "171358",
  "infant-multigrain-cereal" => "170964",
  "infant-oatmeal" => "171360",
  "infant-rice-cereal" => "170969",
  "firm-tofu" => "172475",
  "tofu" => "172476",
  "black-eyed-pea" => "173759",
  "broad-bean" => "173753",
  "lentil" => "172421",
  "lupini-bean" => "172424",
  "mung-bean-sprout" => "169137",
  "oatmeal" => "173905",
  "orange" => "169097",
  "mangosteen" => "169090",
  "peanut-butter" => "172470",
  "plain-whole-milk-yogurt" => "171284",
  "quinoa" => "168917",
  "semolina" => "168933",
  "rambutan" => "168167",
  "spinach" => "168463",
  "split-pea" => "172429",
  "strawberry" => "167762",
  "sweet-potato" => "168483",
  "pea" => "170420",
  "green-pea" => "170420",
  "ground-beef" => "171794",
  "chicken-breast" => "171477",
  "roast-beef" => "171755",
  "turkey" => "171481",
  "mahi-mahi" => "171992",
  "milkfish" => "171995",
  "red-snapper" => "173699",
  "sardine" => "175139",
  "oyster" => "171980",
  "steelhead-trout" => "168060",
  "cheddar-cheese" => "173414",
  "monterey-jack-cheese" => "170844",
  "parmesan-cheese" => "170848",
  "buttermilk-in-food" => "172225",
  "greek-yogurt" => "171304",
  "pasteurized-milk-in-food" => "171265",
  "sour-cream" => "2705614",
  "chicken-egg" => "173424",
  "egg" => "173424",
  "egg-yolk" => "2707174",
  "almond" => "170158",
  "walnut" => "170187",
  "coriander" => "170922",
  "bay-leaf-flavor" => "170917",
  "beef-stew" => "173330",
  "chicken-soup" => "2707134",
  "macaroni-and-cheese" => "173325",
  "mashed-potato" => "2709492",
  "meat-loaf" => "2706499",
  "tomato-soup" => "2709757",
  "vegetable-soup" => "171594",
  "corn-porridge" => "2708374",
}.freeze

# These are real, complete USDA records selected as the closest available
# estimate for a catalog concept that does not have its own complete record.
# Unlike FDC_ID_OVERRIDES, generated descriptions explicitly say that the
# record is representative.
REPRESENTATIVE_FDC_OVERRIDES = {
  "acai" => "173175",
  "fiddlehead-fern" => "170464",
  "pea-protein-patty" => "169067",
  "seitan" => "169067",
  "skyr" => "170894",
  "beef" => "171794",
  "chicken" => "171477",
  "bean-burger" => "2707409",
  "chicken-vegetable-stew" => "2706678",
  "fruit-smoothie-bowl" => "2705513",
  "oat-pancake" => "2708309",
  "spinach-pancake" => "2708309"
}.freeze

# Some catalog labels are varieties, regional names, ground forms, nut
# butters, or homemade dishes without a complete eight-nutrient USDA record.
# Each one is mapped deliberately to a nutritionally close catalog food whose
# USDA record is used as a representative estimate. The generated source
# description preserves that distinction for auditability.
REPRESENTATIVE_ALIASES = {
  "atemoya" => "cherimoya",
  "black-raspberry" => "raspberry",
  "blackcurrant" => "currant",
  "blood-orange" => "orange",
  "cactus-pear" => "prickly-pear",
  "cape-gooseberry" => "gooseberry",
  "cloudberry" => "raspberry",
  "crab-apple" => "apple",
  "finger-lime" => "lime",
  "huckleberry" => "blueberry",
  "marionberry" => "blackberry",
  "pawpaw" => "papaya",
  "pomelo" => "grapefruit",
  "redcurrant" => "currant",
  "satsuma" => "mandarin",
  "tamarillo" => "tomato",
  "ugli-fruit" => "grapefruit",
  "bell-pepper" => "red-bell-pepper",
  "cactus-pad" => "nopales",
  "daikon" => "radish",
  "delicata-squash" => "acorn-squash",
  "edible-fern" => "fiddlehead-fern",
  "french-bean" => "green-bean",
  "kabocha-squash" => "hubbard-squash",
  "malanga" => "taro",
  "pea-shoot" => "pea",
  "wax-bean" => "green-bean",
  "yucca-root" => "cassava",
  "amaranth" => "quinoa",
  "angel-hair-pasta" => "pasta",
  "arborio-rice" => "white-rice",
  "barley-cereal" => "barley",
  "basmati-rice" => "white-rice",
  "black-rice" => "brown-rice",
  "buckwheat-noodle" => "pasta",
  "cassava-flour-porridge" => "cassava",
  "cornmeal" => "grits",
  "einkorn" => "spelt",
  "farro" => "barley",
  "fonio" => "millet",
  "freekeh" => "barley",
  "jasmine-rice" => "white-rice",
  "kamut" => "spelt",
  "kasha" => "buckwheat",
  "orzo" => "pasta",
  "pearl-barley" => "barley",
  "polenta" => "grits",
  "red-rice" => "brown-rice",
  "rice-porridge" => "white-rice",
  "rye" => "barley",
  "sorghum" => "millet",
  "steel-cut-oats" => "oatmeal",
  "teff" => "millet",
  "udon-noodle" => "pasta",
  "wheat-berries" => "spelt",
  "wheat-noodle" => "pasta",
  "whole-wheat-couscous" => "couscous",
  "borlotti-bean" => "cranberry-bean",
  "butter-bean" => "lima-bean",
  "cannellini-bean" => "white-bean",
  "fermented-tofu" => "firm-tofu",
  "french-lentil" => "lentil",
  "green-lentil" => "lentil",
  "moth-bean" => "mung-bean",
  "red-lentil" => "lentil",
  "sprouted-lentil" => "lentil",
  "tempeh" => "firm-tofu",
  "yellow-lentil" => "lentil",
  "yellow-split-pea" => "split-pea",
  "beef-cheek" => "beef",
  "beef-meatball" => "ground-beef",
  "chicken-meatball" => "ground-chicken",
  "duck-breast" => "duck",
  "duck-leg" => "duck",
  "lamb-meatball" => "ground-lamb",
  "pork-meatball" => "ground-pork",
  "turkey-meatball" => "ground-turkey",
  "arctic-char" => "rainbow-trout",
  "barramundi" => "sea-bass",
  "black-cod" => "cod",
  "branzino" => "sea-bass",
  "hake" => "whiting",
  "langoustine" => "shrimp",
  "prawn" => "shrimp",
  "havarti-cheese" => "gouda-cheese",
  "labneh" => "greek-yogurt",
  "mascarpone" => "cream-cheese",
  "coconut-butter" => "coconut-flesh",
  "ground-almond" => "almond",
  "ground-cashew" => "cashew",
  "ground-hazelnut" => "hazelnut",
  "ground-pecan" => "pecan",
  "ground-pistachio" => "pistachio",
  "ground-walnut" => "walnut",
  "hazelnut-butter" => "hazelnut",
  "macadamia-nut-butter" => "macadamia-nut",
  "pecan-butter" => "pecan",
  "pistachio-butter" => "pistachio",
  "walnut-butter" => "walnut",
  "celery-leaf" => "parsley",
  "curry-leaf" => "oregano",
  "fennel-frond" => "fennel-bulb",
  "galangal" => "ginger",
  "lemon-balm" => "mint",
  "lemongrass" => "ginger",
  "mint" => "spearmint",
  "za-atar-herb-blend" => "oregano",
  "apple-oatmeal" => "oatmeal",
  "avocado-toast" => "avocado",
  "broccoli-fritter" => "broccoli",
  "chickpea-pasta" => "pasta",
  "egg-fried-rice" => "rice",
  "millet-porridge" => "millet",
  "mung-dal" => "mung-bean",
  "risotto" => "rice",
  "sweet-potato-fritter" => "sweet-potato",
  "tofu-scramble" => "firm-tofu",
  "turkey-chili" => "ground-turkey"
}.freeze

options = {
  source: "LittleWindows/Services/SolidsReferenceCatalog.swift",
  foundation: "/tmp/lw-fdc/FoodData_Central_foundation_food_json_2026-04-30.json",
  sr: "/tmp/lw-fdc/FoodData_Central_sr_legacy_food_json_2018-04.json",
  fndds: "/tmp/lw-fdc/surveyDownload.json",
  dump_index: nil,
  swift_output: nil,
  update_source: nil
}

OptionParser.new do |parser|
  parser.on("--source PATH") { |value| options[:source] = value }
  parser.on("--foundation PATH") { |value| options[:foundation] = value }
  parser.on("--sr PATH") { |value| options[:sr] = value }
  parser.on("--fndds PATH") { |value| options[:fndds] = value }
  parser.on("--dump-index PATH") { |value| options[:dump_index] = value }
  parser.on("--swift-output PATH") { |value| options[:swift_output] = value }
  parser.on("--update-source PATH") { |value| options[:update_source] = value }
end.parse!

def normalized(value)
  value
    .unicode_normalize(:nfkd)
    .encode("ASCII", invalid: :replace, undef: :replace, replace: "")
    .downcase
    .gsub("&", " and ")
    .gsub(/[^a-z0-9]+/, " ")
    .strip
    .gsub(/\s+/, " ")
end

def singular(value)
  value.split.map do |word|
    if word.end_with?("ies") && word.length > 4
      "#{word[0...-3]}y"
    elsif word.end_with?("oes") && word.length > 4
      word[0...-2]
    elsif word.end_with?("ses") && word.length > 4
      word[0...-2]
    elsif word.end_with?("s") && !word.end_with?("ss") && word.length > 3
      word[0...-1]
    else
      word
    end
  end.join(" ")
end

def slug(value)
  normalized(value).gsub(/[^a-z0-9]+/, "-").gsub(/^-|-$/, "")
end

def catalog_foods(path)
  source = File.read(path)
  CATEGORY_NAMES.flat_map do |category|
    match = source.match(/private static let #{category}Names = """\s*(.*?)\s*"""/m)
    abort "Missing #{category}Names in #{path}" unless match
    match[1].split(";").map(&:strip).reject(&:empty?).map do |name|
      { id: slug(name), name: name, category: category }
    end
  end
end

def nutrient_values(food)
  nutrients = Array(food["foodNutrients"])
  NUTRIENT_IDS.transform_values do |ids|
    nutrients.find do |entry|
      nutrient_id = entry.dig("nutrient", "id") || entry["nutrientId"]
      ids.include?(nutrient_id)
    end&.fetch("amount", nil)
  end
end

def load_foods(path, root_key, data_type)
  JSON.parse(File.read(path)).fetch(root_key).each_with_object([]) do |food, result|
    next unless food.is_a?(Hash)
    values = nutrient_values(food)
    next unless values.values.all? { |value| value.is_a?(Numeric) && value.finite? && value >= 0 }

    description = food.fetch("description")
    normalized_description = normalized(description)
    result << {
      fdc_id: food.fetch("fdcId").to_s,
      description: description,
      normalized: normalized_description,
      singular: singular(normalized_description),
      values: values,
      data_type: data_type,
      portions: food.fetch("foodPortions", [])
    }
  end
end

foods = []
foods.concat(load_foods(options[:foundation], "FoundationFoods", "Foundation"))
foods.concat(load_foods(options[:sr], "SRLegacyFoods", "SR Legacy"))
foods.concat(load_foods(options[:fndds], "SurveyFoods", "FNDDS 2021-2023"))
foods_by_fdc_id = foods.each_with_object({}) { |food, result| result[food[:fdc_id]] = food }

if options[:dump_index]
  File.open(options[:dump_index], "w") do |file|
    foods.sort_by { |food| [food[:description], food[:fdc_id]] }.each do |food|
      file.puts [food[:fdc_id], food[:data_type], food[:description], *food[:values].values].join("\t")
    end
  end
end

STOP_WORDS = %w[
  and or with without added additions cooked raw fresh frozen canned prepared
  style regular plain all commercial varieties ns as to type from made in food
].freeze

foods_by_token = Hash.new { |hash, key| hash[key] = [] }
foods.each do |food|
  food[:singular].split.uniq.each { |token| foods_by_token[token] << food }
end

def candidate_score(catalog_food, food)
  query = normalized(catalog_food[:name])
  query_singular = singular(query)
  description = food[:normalized]
  description_singular = food[:singular]
  first_clause = description.split(" ").take_while { |token| token != "with" }.join(" ")
  tokens = query_singular.split - STOP_WORDS
  description_tokens = description_singular.split
  matched_tokens = tokens.count { |token| description_tokens.include?(token) }
  missing_tokens = tokens.length - matched_tokens

  score = 0
  padded_description = " #{description} "
  padded_singular = " #{description_singular} "
  phrase_bonus = 0
  phrase_bonus = [phrase_bonus, 1_000].max if description == query
  phrase_bonus = [phrase_bonus, 800].max if description.start_with?("#{query} ")
  phrase_bonus = [phrase_bonus, 760].max if description_singular.start_with?("#{query_singular} ")
  phrase_bonus = [phrase_bonus, 720].max if padded_description.include?(" #{query} ")
  phrase_bonus = [phrase_bonus, 680].max if padded_singular.include?(" #{query_singular} ")
  score += phrase_bonus
  score += matched_tokens * 120
  score -= missing_tokens * 360
  score += 140 if missing_tokens.zero?
  score -= [description_tokens.length - tokens.length, 0].max * 2
  score += { "Foundation" => 18, "SR Legacy" => 12, "FNDDS 2021-2023" => 5 }.fetch(food[:data_type])

  category = catalog_food[:category]
  if category == "fruit"
    score += 120 if description.include?("raw")
    score -= 1_600 if description.match?(/juice|drink|syrup|sweetened|dessert|pie|sauce|filling|concentrate|beverage|canned|leaves|peel|milk/)
  elsif %w[vegetable grain plantProtein].include?(category)
    score += 100 if description.match?(/cooked|boiled|baked|steamed/)
    score += 35 if description.include?("without salt")
    score -= 1_600 if description.match?(/restaurant|fast food|chips|snack|dip|salad|casserole|soup|curry|sauce|stuffing|dehydrated|pickled|juice|rings|paste|puree/)
    score -= 1_000 if !query.include?("greens") && description.include?("greens")
    score -= 1_000 if category == "grain" && description.match?(/taco|beans and|chocolate flavored|gluten free/) && !query.match?(/taco|beans|chocolate|gluten/)
    score -= 1_600 if category == "grain" && description.match?(/cookie|pastry|babyfood/) && !query.match?(/cookie|pastry|infant/)
    score -= 1_000 if category == "plantProtein" && description.match?(/flour|yogurt|curd cheese/) && !query.match?(/flour|yogurt|cheese/)
    score -= 200 if description.include?("babyfood") && !query.include?("infant")
  elsif %w[meat seafood egg].include?(category)
    score += 110 if description.match?(/cooked|roasted|broiled|baked|poached|hard boiled|dry heat|moist heat|simmered|braised/)
    score -= 1_600 if description.match?(/breaded|fried|battered|restaurant|fast food|cake|patty|sandwich|sausage|salami|bratwurst|spread|stuffed|coated|nugget|deli|cured|salad|sauce|separable fat|roll|pre basted|subway|milk/)
    score -= 1_600 if category == "seafood" && description.include?("oil")
  elsif category == "dairy"
    score += 100 if description.match?(/whole milk|full fat|plain/)
    score -= 1_600 if description.match?(/lowfat|nonfat|fat free|sweetened|spread|dressing|palak|with fruit|cereal|swisswurst|snack|fast food|pretzel|breadstick/)
  elsif category == "nutAndSeed"
    score += 100 if description.match?(/raw|without salt|plain/)
    score -= 1_600 if description.match?(/salted|sweetened|with salt|oil|dressing|paste|fish/)
    score -= 1_600 if !query.include?("butter") && description.include?("butter")
    score -= 1_600 if description.include?("honey roasted")
  elsif category == "herbAndFlavor"
    score += 80 if description.match?(/spices|fresh|raw|dried|ground/)
    score -= 1_600 if description.match?(/oil|bun|drink|julep|cheese|candy/)
  elsif category == "preparedFood"
    score += 120 if food[:data_type] == "FNDDS 2021-2023"
    score -= 220 if description.match?(/sandwich|with rice|with meat/) && !query.match?(/sandwich|rice|meat/)
  end

  score -= 110 if description.match?(/babyfood|infant formula/) && !query.include?("infant")
  score -= 90 if description.match?(/pillsbury|campbell|kraft|gerber|mcdonald|wendy|restaurant/)
  score -= 1_600 if category == "egg" && description.match?(/foo yung/)
  score += 10 if first_clause.include?(tokens.first.to_s)
  score
end

def ranked_candidates(catalog_food, foods, foods_by_token)
  query_tokens = singular(normalized(catalog_food[:name])).split - STOP_WORDS
  candidate_pool = query_tokens.flat_map { |token| foods_by_token[token] }.uniq
  candidate_pool = foods if candidate_pool.empty?
  candidate_pool
    .map { |food| [candidate_score(catalog_food, food), food] }
    .sort_by { |score, food| [-score, food[:description].length, food[:fdc_id]] }
    .first(5)
end

def swift_string(value)
  value.to_s.gsub("\\", "\\\\").gsub('"', '\\"').gsub("\n", " ")
end

def swift_number(value)
  formatted = format("%.8g", value)
  formatted.include?(".") ? formatted : "#{formatted}.0"
end

def portion_unit(portion)
  label = normalized([
    portion.dig("measureUnit", "name"),
    portion.dig("measureUnit", "abbreviation"),
    portion["modifier"]
  ].compact.join(" "))

  return "teaspoon" if label.match?(/\bteaspoon\b|\btsp\b/)
  return "tablespoon" if label.match?(/\btablespoon\b|\btbsp\b/)
  return "cup" if label.match?(/\bcup\b/)
  return "serving" if label.match?(/\bserving\b/)
  return "piece" if label.match?(/\bpiece\b|\bitem\b|\bmedium\b|\bone\b|\bwhole\b|\bfruit\b|\begg\b/)

  nil
end

def selected_portions(food)
  candidates = Array(food[:portions]).each_with_object([]) do |portion, result|
    unit = portion_unit(portion)
    grams = portion["gramWeight"]
    amount = portion["amount"] || portion["value"] || 1
    next unless unit && grams.is_a?(Numeric) && amount.is_a?(Numeric)
    next unless grams.finite? && amount.finite? && grams.positive? && amount.positive?

    modifier = portion["modifier"].to_s
    preference = case unit
                 when "piece"
                   modifier.match?(/\bmedium\b/i) ? 0 : 10
                 when "cup"
                   modifier.match?(/\bchopped\b|\bdiced\b|\bsliced\b/i) ? 1 : 0
                 else
                   0
                 end
    result << [unit, grams / amount, preference, modifier]
  end

  candidates
    .group_by(&:first)
    .transform_values { |values| values.min_by { |value| [value[2], value[3].length] } }
    .values
    .sort_by(&:first)
    .map { |unit, grams, _preference, modifier| [unit, grams, modifier] }
end

catalog = catalog_foods(options[:source])
catalog_by_id = catalog.each_with_object({}) { |food, result| result[food[:id]] = food }
selection_cache = {}

select_food = lambda do |catalog_food, path = []|
  return selection_cache.fetch(catalog_food[:id]) if selection_cache.key?(catalog_food[:id])
  abort "Representative alias cycle: #{(path + [catalog_food[:id]]).join(' -> ')}" if path.include?(catalog_food[:id])

  if (fdc_id = FDC_ID_OVERRIDES[catalog_food[:id]])
    food = foods_by_fdc_id[fdc_id]
    abort "Missing complete USDA record #{fdc_id} for #{catalog_food[:id]}" unless food
    selection_cache[catalog_food[:id]] = {
      food: food,
      representative: false,
      selection: "override"
    }
  elsif (fdc_id = REPRESENTATIVE_FDC_OVERRIDES[catalog_food[:id]])
    food = foods_by_fdc_id[fdc_id]
    abort "Missing complete representative USDA record #{fdc_id} for #{catalog_food[:id]}" unless food
    selection_cache[catalog_food[:id]] = {
      food: food,
      representative: true,
      selection: "representative-fdc"
    }
  elsif (alias_id = REPRESENTATIVE_ALIASES[catalog_food[:id]])
    target = catalog_by_id[alias_id]
    abort "Unknown representative alias #{catalog_food[:id]} -> #{alias_id}" unless target
    target_selection = select_food.call(target, path + [catalog_food[:id]])
    selection_cache[catalog_food[:id]] = {
      food: target_selection[:food],
      representative: true,
      selection: "representative:#{alias_id}"
    }
  else
    candidates = ranked_candidates(catalog_food, foods, foods_by_token)
    abort "No complete USDA candidates for #{catalog_food[:id]}" if candidates.empty?
    best_score, best = candidates.first
    abort "Low-confidence automatic match for #{catalog_food[:id]}: #{best_score}:#{best[:fdc_id]}:#{best[:description]}" if best_score < 300
    selection_cache[catalog_food[:id]] = {
      food: best,
      representative: false,
      selection: "automatic:#{best_score}",
      candidates: candidates
    }
  end
end

selections = catalog.map { |catalog_food| [catalog_food, select_food.call(catalog_food)] }
abort "Expected 535 catalog foods, found #{selections.count}" unless selections.count == 535
abort "Catalog food IDs are not unique" unless catalog_by_id.count == catalog.count

selections.each do |catalog_food, selection|
  best = selection[:food]
  values = best[:values]
  abort "Incomplete nutrients for #{catalog_food[:id]}" unless values.values.all? { |value| value.is_a?(Numeric) && value.finite? && value >= 0 }

  candidates = selection[:candidates] || ranked_candidates(catalog_food, foods, foods_by_token)
  best_score = candidates.find { |_score, food| food[:fdc_id] == best[:fdc_id] }&.first || candidate_score(catalog_food, best)
  runner_up_score = candidates.reject { |_score, food| food[:fdc_id] == best[:fdc_id] }.first&.first || 0

  nutrient_output = values.values.map { |value| format("%.6g", value) }.join("|")
  puts [
    catalog_food[:category], catalog_food[:id], catalog_food[:name], best_score,
    best_score - runner_up_score, best[:fdc_id], best[:data_type], best[:description],
    nutrient_output, selection[:selection],
    candidates.drop(1).map { |score, food| "#{score}:#{food[:fdc_id]}:#{food[:description]}" }.join(" || ")
  ].join("\t")
end

if options[:swift_output] || options[:update_source]
  version = "USDA-FDC-Foundation-2026-04+SR-Legacy-2018-04+FNDDS-2021-2023"
  lines = []
  lines << "/// Generated by Scripts/build_solids_nutrition_catalog.rb from official USDA FoodData Central data."
  lines << "/// All values are per 100 grams and include all eight nutrients tracked by the app."
  lines << "/// Representative estimates are labeled in sourceDescription and intentionally omit item/volume portions."
  lines << "enum SolidsNutritionCatalog {"
  lines << "    static let version = \"#{version}\""
  lines << ""
  lines << "    static func reference(foodID: String) -> SolidNutritionReference? {"
  lines << "        switch foodID {"
  selections.each_with_index do |(catalog_food, selection), index|
    food = selection[:food]
    values = food[:values]
    description = if selection[:representative]
                    "Representative USDA estimate for #{catalog_food[:name]}: #{food[:description]}"
                  else
                    food[:description]
                  end
    portions = selection[:representative] ? [] : selected_portions(food)
    portion_source = portions.map do |unit, grams, modifier|
      ".#{unit}: (#{swift_number(grams)}, \"#{swift_string(modifier.empty? ? unit.capitalize : modifier)}\")"
    end.join(", ")
    portion_literal = portion_source.empty? ? "[:]" : "[#{portion_source}]"
    _ = index
    lines << "        case \"#{swift_string(catalog_food[:id])}\":"
    lines << "            reference(\"#{food[:fdc_id]}\", \"#{swift_string(description)}\", #{values.values.map { |value| swift_number(value) }.join(', ')}, portions: #{portion_literal})"
  end
  lines << "        default: nil"
  lines << "        }"
  lines << "    }"
  lines << ""
  lines << "    static let supportedFoodIDs: Set<String> = ["
  selections.each_with_index do |(catalog_food, _selection), index|
    comma = index == selections.length - 1 ? "" : ","
    lines << "        \"#{swift_string(catalog_food[:id])}\"#{comma}"
  end
  lines << "    ]"
  lines << ""
  lines << "    private static func reference("
  lines << "        _ fdcID: String,"
  lines << "        _ description: String,"
  lines << "        _ energy: Double,"
  lines << "        _ protein: Double,"
  lines << "        _ fat: Double,"
  lines << "        _ fiber: Double,"
  lines << "        _ iron: Double,"
  lines << "        _ zinc: Double,"
  lines << "        _ calcium: Double,"
  lines << "        _ vitaminC: Double,"
  lines << "        portions: [SolidPortionUnit: (grams: Double, description: String)]"
  lines << "    ) -> SolidNutritionReference {"
  lines << "        SolidNutritionReference("
  lines << "            sourceKind: .usdaFoodDataCentral,"
  lines << "            sourceID: fdcID,"
  lines << "            sourceDescription: description,"
  lines << "            sourceVersion: version,"
  lines << "            basisQuantity: 100,"
  lines << "            basisUnit: .gram,"
  lines << "            basisGrams: 100,"
  lines << "            nutrients: SolidNutritionValues("
  lines << "                energyKilocalories: energy,"
  lines << "                proteinGrams: protein,"
  lines << "                fatGrams: fat,"
  lines << "                fiberGrams: fiber,"
  lines << "                ironMilligrams: iron,"
  lines << "                zincMilligrams: zinc,"
  lines << "                calciumMilligrams: calcium,"
  lines << "                vitaminCMilligrams: vitaminC"
  lines << "            ),"
  lines << "            portions: portions.map {"
  lines << "                SolidNutritionPortion("
  lines << "                    unit: $0.key,"
  lines << "                    gramsPerUnit: $0.value.grams,"
  lines << "                    description: $0.value.description"
  lines << "                )"
  lines << "            }.sorted { $0.unit.rawValue < $1.unit.rawValue }"
  lines << "        )"
  lines << "    }"
  lines << "}"
  generated_source = lines.join("\n") + "\n"
  File.write(options[:swift_output], generated_source) if options[:swift_output]

  if options[:update_source]
    source = File.read(options[:update_source])
    pattern = /(?:\/\/\/ Generated by Scripts\/build_solids_nutrition_catalog\.rb.*?\n\/\/\/ All values are per 100 grams.*?\n\/\/\/ Representative estimates.*?\n)*enum SolidsNutritionCatalog \{.*?\n\}\n\nenum SolidsAllergen/m
    abort "Could not locate SolidsNutritionCatalog in #{options[:update_source]}" unless source.match?(pattern)
    updated = source.sub(pattern, "#{generated_source}\nenum SolidsAllergen")
    File.write(options[:update_source], updated)
  end
end
