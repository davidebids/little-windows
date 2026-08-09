#!/usr/bin/env ruby

require "csv"
require "date"
require "digest"
require "fileutils"
require "json"
require "optparse"
require "set"
require "time"

ENV["TZ"] = "America/Los_Angeles"

options = {
  birth_date: "2026-01-31",
  baby_name: "Sample Child"
}

OptionParser.new do |parser|
  parser.banner = "Usage: convert_legacy_tracker.rb INPUT.csv --output BACKUP.json --summary SUMMARY.md"
  parser.on("--output PATH", "Little Windows JSON backup path") { |value| options[:output] = value }
  parser.on("--summary PATH", "Markdown import report path") { |value| options[:summary] = value }
  parser.on("--birth-date DATE", "Baby birth date (YYYY-MM-DD)") { |value| options[:birth_date] = value }
  parser.on("--baby-name NAME", "Baby profile name") { |value| options[:baby_name] = value }
  parser.on("--merge-backup PATH", "Existing Little Windows backup to preserve") { |value| options[:merge_backup] = value }
  parser.on("--target-profile-id UUID", "Existing child profile that receives converted events") { |value| options[:target_profile_id] = value }
end.parse!

input = ARGV.shift
abort("Missing input CSV") unless input
abort("Missing --output") unless options[:output]
if options[:merge_backup].nil? != options[:target_profile_id].nil?
  abort("--merge-backup and --target-profile-id must be provided together")
end

def deterministic_uuid(value)
  hex = Digest::SHA256.hexdigest(value)[0, 32]
  hex[12] = "5"
  hex[16] = ((hex[16].to_i(16) & 0x3) | 0x8).to_s(16)
  [hex[0, 8], hex[8, 4], hex[12, 4], hex[16, 4], hex[20, 12]].join("-")
end

def parse_time(value)
  return nil if value.nil? || value.empty?

  Time.strptime(value, "%Y-%m-%d %H:%M")
end

def iso8601(value)
  value.utc.iso8601
end

def combined_notes(*parts)
  values = parts.compact.map(&:strip).reject(&:empty?)
  values.empty? ? nil : values.join("\n")
end

def cleaned_text(value)
  value.to_s
    .gsub(/\\n/i, " ")
    .gsub(/\s+/, " ")
    .strip
end

def slug(value)
  value.downcase
    .encode("ASCII", invalid: :replace, undef: :replace, replace: "")
    .gsub(/[^a-z0-9]+/, "-")
    .gsub(/\A-+|-+\z/, "")
end

def solid_food_reference(source_name)
  normalized = cleaned_text(source_name).downcase
  known_foods = {
    "avocado" => ["avocado", "Avocado", []],
    "banana" => ["banana", "Banana", []],
    "carrot" => ["carrot", "Carrot", []],
    "egg" => ["egg", "Egg", ["egg"]],
    "oatmeal" => ["oatmeal", "Oatmeal", []],
    "peach" => ["peach", "Peach", []],
    "peanut butter" => ["peanut-butter", "Peanut butter", ["peanuts"]],
    "pea" => ["pea", "Pea", []],
    "peas" => ["pea", "Pea", []],
    "watermelon" => ["watermelon", "Watermelon", []],
    # The source does not identify the style of yogurt, so preserve it as a
    # custom food instead of guessing one of the app's specific yogurt entries.
    "yogurt" => ["custom-yogurt", "Yogurt", ["milk"]]
  }
  return known_foods.fetch(normalized) if known_foods.key?(normalized)

  display_name = cleaned_text(source_name)
  ["custom-#{slug(display_name)}", display_name, []]
end

def solid_food_details(value, reaction)
  cleaned_text(value).split(/\s*,\s*/).map do |part|
    next if part.empty?

    match = part.match(/\A(.+?)\s+of\s+(.+)\z/i)
    serving_amount = match && cleaned_text(match[1])
    source_name = cleaned_text(match ? match[2] : part)
    food_id, food_name, allergen_ids = solid_food_reference(source_name)
    suspected_reaction = reaction == "sensitivity"
    {
      "foodID" => food_id,
      "foodName" => food_name,
      "allergenIDs" => allergen_ids,
      "confirmedAllergenPortionIDs" => nil,
      "preference" => reaction,
      "servingAmount" => serving_amount,
      "notes" => nil,
      "suspectedReaction" => suspected_reaction,
      "symptoms" => [],
      "severity" => "unknown",
      "onsetMinutes" => nil,
      "durationMinutes" => nil,
      "responseNotes" => suspected_reaction ? "Source export marked this meal as ALLERGIC; no symptoms or severity were included." : "",
      "followUp" => "none"
    }
  end.compact
end

def base_event(index:, suffix:, type:, start_time:, end_time: nil, title: nil, notes: nil)
  {
    "id" => deterministic_uuid("legacy-tracker-event-#{index}-#{suffix}"),
    "typeRawValue" => type,
    "title" => title,
    "startDate" => iso8601(start_time),
    "endDate" => end_time ? iso8601(end_time) : nil,
    "createdAt" => iso8601(start_time),
    "updatedAt" => iso8601(end_time || start_time),
    "caregiverName" => nil,
    "notes" => notes,
    "sleepKindRawValue" => nil,
    "feedKindRawValue" => nil,
    "amountOz" => nil,
    "foodDescription" => nil,
    "solidReactionRawValue" => nil,
    "solidTextureRawValue" => nil,
    "solidFeedingStyleRawValue" => nil,
    "solidAllergenExposure" => nil,
    "solidSensitivityObserved" => nil,
    "solidFoodDetailsJSON" => nil,
    "nursingSideRawValue" => nil,
    "activeNursingSideRawValue" => nil,
    "leftDurationSeconds" => nil,
    "rightDurationSeconds" => nil,
    "diaperKindRawValue" => nil,
    "stoolColor" => nil,
    "stoolTexture" => nil,
    "bookTitle" => nil,
    "medicineName" => nil,
    "dose" => nil,
    "doseUnit" => nil,
    "reason" => nil
  }
end

def nursing_segment(value)
  match = value&.match(/\A(\d{2}):(\d{2})([LR])\z/)
  return nil unless match

  minutes = (match[1].to_i * 60) + match[2].to_i
  return nil if minutes <= 0

  {
    minutes: minutes,
    side: match[3] == "L" ? "left" : "right"
  }
end

def parse_amount(value)
  value&.match(/([\d.]+)\s*oz/i)&.[](1)&.to_f
end

def parse_dose(value)
  match = value&.strip&.match(/\A([\d.]+)\s*(.*)\z/)
  return [nil, nil] unless match

  unit = match[2].strip
  [match[1].to_f, unit.empty? ? nil : unit]
end

def parse_compound_measurement(value, suffix)
  match = value&.strip&.match(/\A(\d+)(?:\.(\d+))?#{Regexp.escape(suffix)}\z/i)
  return [nil, nil] unless match

  major = match[1].to_i
  encoded_minor = match[2]
  minor =
    if encoded_minor.nil?
      0.0
    elsif encoded_minor.length == 1
      encoded_minor.to_f
    else
      encoded_minor.to_f / 10
    end
  [major, minor]
end

def parse_inches(value)
  value&.strip&.match(/\A([\d.]+)\s*in\z/i)&.[](1)&.to_f
end

rows = CSV.read(input, headers: true)
events = []
source_counts = Hash.new(0)
conversion_notes = Hash.new(0)

sleep_rows = rows.each_with_index
  .select { |row, _| row["Type"] == "Sleep" }
  .map do |row, offset|
    {
      offset: offset,
      start_time: parse_time(row["Start"]),
      end_time: parse_time(row["End"]),
      night: false
    }
  end
  .sort_by { |value| value[:start_time] }

sleep_rows.each_with_index do |sleep, index|
  crosses_midnight = sleep[:end_time].to_date > sleep[:start_time].to_date
  sleep[:night] = sleep[:start_time].hour >= 19 || sleep[:start_time].hour < 6 || crosses_midnight

  next if sleep[:night] || sleep[:start_time].hour >= 9 || index == 0

  previous = sleep_rows[index - 1]
  wake_minutes = (sleep[:start_time] - previous[:end_time]) / 60
  sleep[:night] = previous[:night] && wake_minutes <= 90
end

sleep_kind_by_offset = sleep_rows.to_h {
  |sleep| [sleep[:offset], sleep[:night] ? "nightSleep" : "nap"]
}

rows.each_with_index do |row, offset|
  row_number = offset + 2
  source_type = row["Type"]
  source_counts[source_type] += 1
  start_time = parse_time(row["Start"])
  source_end = parse_time(row["End"])
  source_notes = row["Notes"]

  case source_type
  when "Sleep"
    sleep_metadata = [
      row["Start Condition"] && "Start condition: #{row["Start Condition"]}",
      row["Start Location"]&.length.to_i.between?(1, 80) && "Location: #{row["Start Location"]}",
      row["End Condition"] && "End condition: #{row["End Condition"]}"
    ].select { |value| value.is_a?(String) }
    event = base_event(
      index: row_number,
      suffix: "sleep",
      type: "sleep",
      start_time: start_time,
      end_time: source_end,
      notes: combined_notes(source_notes, *sleep_metadata)
    )
    event["sleepKindRawValue"] = sleep_kind_by_offset.fetch(offset)
    events << event
  when "Feed"
    if row["Start Location"] == "Breast"
      segments = [row["Start Condition"], row["End Condition"]]
        .map { |value| nursing_segment(value) }
        .compact
      if segments.empty?
        event = base_event(
          index: row_number,
          suffix: "breast-unspecified",
          type: "feed",
          start_time: start_time,
          end_time: source_end || start_time,
          notes: combined_notes(source_notes, "Breast feed; side was not recorded in the source export.")
        )
        event["feedKindRawValue"] = "other"
        event["foodDescription"] = "Breast feed"
        events << event
        conversion_notes["breast feeds without a usable side"] += 1
      else
        cursor = start_time
        segments.each_with_index do |segment, segment_index|
          segment_end = cursor + (segment[:minutes] * 60)
          event = base_event(
            index: row_number,
            suffix: "nursing-#{segment_index}",
            type: "nursing",
            start_time: cursor,
            end_time: segment_end,
            notes: source_notes
          )
          event["nursingSideRawValue"] = segment[:side]
          duration_key = segment[:side] == "left" ? "leftDurationSeconds" : "rightDurationSeconds"
          event[duration_key] = segment[:minutes] * 60
          events << event
          cursor = segment_end
        end
        conversion_notes["breast feeds split into two one-side events"] += 1 if segments.length == 2
      end
    else
      event = base_event(
        index: row_number,
        suffix: "bottle",
        type: "feed",
        start_time: start_time,
        end_time: source_end || start_time,
        notes: source_notes
      )
      event["feedKindRawValue"] = "bottle"
      event["amountOz"] = parse_amount(row["End Condition"])
      event["foodDescription"] = row["Start Condition"]
      events << event
    end
  when "Solids"
    reaction = case cleaned_text(row["End Condition"]).upcase
               when "LOVED" then "loved"
               when "ALLERGIC" then "sensitivity"
               else "unknown"
               end
    details = solid_food_details(row["Start Condition"], reaction)
    event = base_event(
      index: row_number,
      suffix: "solids",
      type: "feed",
      start_time: start_time,
      end_time: source_end || start_time,
      notes: source_notes
    )
    event["feedKindRawValue"] = "solid"
    event["foodDescription"] = details.map { |detail| detail["foodName"] }.join(", ")
    event["solidReactionRawValue"] = reaction
    event["solidAllergenExposure"] = details.any? { |detail| !detail["allergenIDs"].empty? }
    event["solidSensitivityObserved"] = reaction == "sensitivity"
    event["solidFoodDetailsJSON"] = JSON.generate(details)
    events << event
  when "Diaper"
    details = row["End Condition"].to_s
    lowered = details.downcase
    event = base_event(
      index: row_number,
      suffix: "diaper",
      type: "diaper",
      start_time: start_time,
      notes: combined_notes(
        source_notes,
        row["Start Location"] && "Condition: #{row["Start Location"]}",
        details.empty? ? nil : "Imported details: #{details}"
      )
    )
    event["diaperKindRawValue"] =
      if lowered.include?("both") || (lowered.include?("pee") && lowered.include?("poo"))
        "both"
      elsif lowered.include?("poo")
        "dirty"
      else
        "wet"
      end
    color = row["Duration"]
    event["stoolColor"] = color unless color.nil? || color.match?(/\A\d{2}:\d{2}\z/)
    event["stoolTexture"] = lowered.match(/poo:([a-z]+)/)&.[](1)&.capitalize
    events << event
  when "Tummy time"
    events << base_event(
      index: row_number,
      suffix: "tummy",
      type: "tummyTime",
      start_time: start_time,
      end_time: source_end || start_time,
      notes: source_notes
    )
  when "Story time"
    events << base_event(
      index: row_number,
      suffix: "reading",
      type: "reading",
      start_time: start_time,
      end_time: source_end || start_time,
      notes: source_notes
    )
  when "Bath"
    events << base_event(
      index: row_number,
      suffix: "bath",
      type: "bath",
      start_time: start_time,
      end_time: source_end || start_time,
      notes: source_notes
    )
  when "Meds"
    dose, unit = parse_dose(row["Start Condition"])
    event = base_event(
      index: row_number,
      suffix: "medicine",
      type: "medicine",
      start_time: start_time,
      notes: source_notes
    )
    event["medicineName"] = row["Start Location"] || "Medicine"
    event["dose"] = dose
    event["doseUnit"] = unit
    events << event
  when "Temp"
    value = row["Start Condition"]
    events << base_event(
      index: row_number,
      suffix: "temperature",
      type: "custom",
      title: "Temperature",
      start_time: start_time,
      end_time: start_time,
      notes: combined_notes(value, source_notes)
    )
  when "Growth"
    weight_pounds, weight_ounces = parse_compound_measurement(
      row["Start Condition"],
      "lbs.oz"
    )
    height_feet, height_inches = parse_compound_measurement(
      row["Start Location"],
      "ft.in"
    )
    head_circumference_inches = parse_inches(row["End Condition"])
    event = base_event(
      index: row_number,
      suffix: "growth",
      type: "growth",
      start_time: start_time,
      end_time: start_time,
      notes: source_notes
    )
    event["weightPounds"] = weight_pounds
    event["weightOunces"] = weight_ounces
    event["heightFeet"] = height_feet
    event["heightInches"] = height_inches
    event["headCircumferenceInches"] = head_circumference_inches
    event["growthSexRawValue"] = "male"
    event["growthSourceRawValue"] = "other"
    events << event
  when "Pump"
    details = [
      row["Start Condition"] && "Left: #{row["Start Condition"]}",
      row["End Condition"] && "Right: #{row["End Condition"]}",
      source_notes
    ]
    events << base_event(
      index: row_number,
      suffix: "pump",
      type: "custom",
      title: "Pump",
      start_time: start_time,
      end_time: source_end || start_time,
      notes: combined_notes(*details)
    )
  else
    conversion_notes["unmapped #{source_type} rows"] += 1
  end
end

events.sort_by! { |event| event["startDate"] }
birth_time = Time.strptime(options[:birth_date], "%Y-%m-%d")
latest_time = events.map { |event| Time.iso8601(event["updatedAt"]) }.max

profile = {
  "id" => deterministic_uuid("legacy-tracker-profile-#{options[:baby_name]}"),
  "name" => options[:baby_name],
  "birthDate" => iso8601(birth_time),
  "sexRawValue" => "male",
  "birthWeightKilograms" => nil,
  "birthLengthCentimeters" => nil,
  "birthHeadCircumferenceCentimeters" => nil,
  "notes" => "History imported from a legacy tracker. Birth date inferred from the first newborn growth entry.",
  "createdAt" => iso8601(birth_time),
  "updatedAt" => iso8601(latest_time)
}

backup = {
  "version" => 3,
  "exportedAt" => iso8601(latest_time),
  "profiles" => [profile],
  "events" => events,
  "predictionRecords" => []
}
recovered_solid_event_count = 0

if options[:merge_backup]
  existing_backup = JSON.parse(File.read(options[:merge_backup]))
  target_profile_id = options[:target_profile_id].upcase
  target_profile = existing_backup.fetch("profiles", []).find do |value|
    value["id"].to_s.upcase == target_profile_id
  end
  abort("Target profile was not found in the existing backup") unless target_profile
  unless target_profile["profileTypeRawValue"].to_s.empty? || target_profile["profileTypeRawValue"] == "child"
    abort("Target profile must be a child profile")
  end

  imported_event_ids = events.map { |event| event.fetch("id") }.to_set
  conflicting_event = existing_backup.fetch("events", []).find do |event|
    imported_event_ids.include?(event["id"]) && event["profileID"].to_s.upcase != target_profile_id
  end
  abort("An imported event ID belongs to another profile in the existing backup") if conflicting_event

  events.each do |event|
    event["profileID"] = target_profile["id"]
    event["profileTypeSnapshotRawValue"] = "child"
  end
  preserved_events = existing_backup.fetch("events", []).reject do |event|
    imported_event_ids.include?(event["id"])
  end
  merged_events = preserved_events + events
  merged_event_ids = merged_events.map { |event| event.fetch("id") }.to_set
  orphan_solid_items = existing_backup.fetch("solidFoodEventItems", []).group_by do |item|
    item.fetch("eventID")
  end.reject { |event_id, _| merged_event_ids.include?(event_id) }
  orphan_solid_items.each do |event_id, items|
    profile_id = items.first.fetch("profileID")
    profile_type = existing_backup.fetch("profiles", []).find do |value|
      value.fetch("id") == profile_id
    end&.fetch("profileTypeRawValue", "child")
    details = items.map do |item|
      {
        "foodID" => item.fetch("foodID"),
        "foodName" => item.fetch("foodNameSnapshot"),
        "allergenIDs" => JSON.parse(item.fetch("allergenIDsJSON", "[]")),
        "confirmedAllergenPortionIDs" => JSON.parse(
          item.fetch("confirmedAllergenPortionIDsJSON", "[]")
        ),
        "preference" => item.fetch("reactionRawValue", "unknown"),
        "servingAmount" => item["servingAmount"].to_s.empty? ? nil : item["servingAmount"],
        "notes" => item["notes"].to_s.empty? ? nil : item["notes"],
        "suspectedReaction" => item.fetch("suspectedReaction", false),
        "symptoms" => JSON.parse(item.fetch("symptomIDsJSON", "[]")),
        "severity" => item.fetch("severityRawValue", "unknown"),
        "onsetMinutes" => item["onsetMinutes"],
        "durationMinutes" => item["durationMinutes"],
        "responseNotes" => item.fetch("responseNotes", ""),
        "followUp" => item.fetch("followUpRawValue", "none")
      }
    end
    start_date = items.map { |item| item.fetch("createdAt") }.min
    updated_at = items.map { |item| item.fetch("updatedAt") }.max
    sensitivity_observed = details.any? { |detail| detail["suspectedReaction"] }
    merged_events << {
      "id" => event_id,
      "profileID" => profile_id,
      "profileTypeSnapshotRawValue" => profile_type,
      "typeRawValue" => "feed",
      "title" => nil,
      "startDate" => start_date,
      "endDate" => start_date,
      "createdAt" => start_date,
      "updatedAt" => updated_at,
      "caregiverName" => nil,
      "notes" => nil,
      "feedKindRawValue" => "solid",
      "foodDescription" => details.map { |detail| detail["foodName"] }.join(", "),
      "solidReactionRawValue" => sensitivity_observed ? "sensitivity" : details.first.fetch("preference"),
      "solidAllergenExposure" => details.any? { |detail| !detail["allergenIDs"].empty? },
      "solidSensitivityObserved" => sensitivity_observed,
      "solidFoodDetailsJSON" => JSON.generate(details)
    }
    recovered_solid_event_count += 1
  end
  existing_backup["events"] = merged_events.sort_by { |event| event.fetch("startDate") }
  existing_backup["exportedAt"] = Time.now.utc.iso8601
  backup = existing_backup
end

FileUtils.mkdir_p(File.dirname(options[:output])) unless File.dirname(options[:output]) == "."
File.write(options[:output], JSON.pretty_generate(backup) + "\n")

sleep_events = events.select { |event| event["typeRawValue"] == "sleep" }
nap_events = sleep_events.select { |event| event["sleepKindRawValue"] == "nap" }
night_events = sleep_events.select { |event| event["sleepKindRawValue"] == "nightSleep" }
event_counts = events.group_by { |event| event["typeRawValue"] }.transform_values(&:length).sort
tracked_days = (
  (Date.parse(rows.map { |row| row["Start"] }.max) - Date.parse(rows.map { |row| row["Start"] }.min)).to_i + 1
)
source_start_date = Date.parse(rows.map { |row| row["Start"] }.min)
source_end_date = Date.parse(rows.map { |row| row["Start"] }.max)

if options[:summary]
  FileUtils.mkdir_p(File.dirname(options[:summary])) unless File.dirname(options[:summary]) == "."
  lines = [
    "# Legacy Import Summary",
    "",
    "- Source rows: #{rows.length}",
    "- Converted Little Windows events: #{events.length}",
    "- Date range: #{source_start_date} to #{source_end_date} (#{tracked_days} days)",
    "- Sleep logs: #{sleep_events.length} (#{nap_events.length} naps, #{night_events.length} night segments)",
    "- Inferred birth date: #{options[:birth_date]}",
    options[:merge_backup] ? "- Output mode: merged into an existing child profile while preserving the current backup" : nil,
    "",
    "## Converted Event Counts",
    ""
  ]
  lines.compact!
  event_counts.each { |type, count| lines << "- #{type}: #{count}" }
  lines += ["", "## Conversion Decisions", ""]
  conversion_notes.sort.each { |label, count| lines << "- #{label}: #{count}" }
  lines += [
    "",
    "Breast feeds with two recorded sides are represented as two sequential nursing events. No nursing event uses a Both side.",
    "Night sleep is classified as an overnight sequence, including early-morning sleep that resumes within 90 minutes of the preceding night segment.",
    "Growth records are converted to native growth events. Temperature and pumping records are preserved as custom events.",
    "Solid-food records are converted to native solid-feed events with source serving amounts and preferences. A source ALLERGIC label is preserved as a suspected sensitivity without inventing symptoms, severity, or a diagnosis."
  ]
  File.write(options[:summary], lines.join("\n") + "\n")
end

puts JSON.pretty_generate(
  source_rows: rows.length,
  converted_events: events.length,
  event_counts: event_counts.to_h,
  sleep_logs: sleep_events.length,
  naps: nap_events.length,
  night_segments: night_events.length,
  conversion_notes: conversion_notes.sort.to_h,
  recovered_solid_events: recovered_solid_event_count,
  merge_backup: options[:merge_backup],
  target_profile_id: options[:target_profile_id],
  output: options[:output],
  summary: options[:summary]
)
