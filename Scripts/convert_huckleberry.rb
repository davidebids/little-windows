#!/usr/bin/env ruby

require "csv"
require "date"
require "digest"
require "fileutils"
require "json"
require "optparse"
require "time"

ENV["TZ"] = "America/Los_Angeles"

options = {
  birth_date: "2026-01-31",
  baby_name: "Ethan"
}

OptionParser.new do |parser|
  parser.banner = "Usage: convert_huckleberry.rb INPUT.csv --output BACKUP.json --summary SUMMARY.md"
  parser.on("--output PATH", "Little Windows JSON backup path") { |value| options[:output] = value }
  parser.on("--summary PATH", "Markdown import report path") { |value| options[:summary] = value }
  parser.on("--birth-date DATE", "Baby birth date (YYYY-MM-DD)") { |value| options[:birth_date] = value }
  parser.on("--baby-name NAME", "Baby profile name") { |value| options[:baby_name] = value }
end.parse!

input = ARGV.shift
abort("Missing input CSV") unless input
abort("Missing --output") unless options[:output]

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

def base_event(index:, suffix:, type:, start_time:, end_time: nil, title: nil, notes: nil)
  {
    "id" => deterministic_uuid("huckleberry-event-#{index}-#{suffix}"),
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
          notes: combined_notes(source_notes, "Breast feed; side was not recorded in Huckleberry.")
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
        details.empty? ? nil : "Huckleberry details: #{details}"
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
  "id" => deterministic_uuid("huckleberry-profile-#{options[:baby_name]}"),
  "name" => options[:baby_name],
  "birthDate" => iso8601(birth_time),
  "sexRawValue" => "male",
  "birthWeightKilograms" => nil,
  "birthLengthCentimeters" => nil,
  "birthHeadCircumferenceCentimeters" => nil,
  "notes" => "History imported from Huckleberry. Birth date inferred from the first newborn growth entry.",
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
    "# Huckleberry Import Summary",
    "",
    "- Source rows: #{rows.length}",
    "- Converted Little Windows events: #{events.length}",
    "- Date range: #{source_start_date} to #{source_end_date} (#{tracked_days} days)",
    "- Sleep logs: #{sleep_events.length} (#{nap_events.length} naps, #{night_events.length} night segments)",
    "- Inferred birth date: #{options[:birth_date]}",
    "",
    "## Converted Event Counts",
    ""
  ]
  event_counts.each { |type, count| lines << "- #{type}: #{count}" }
  lines += ["", "## Conversion Decisions", ""]
  conversion_notes.sort.each { |label, count| lines << "- #{label}: #{count}" }
  lines += [
    "",
    "Breast feeds with two recorded sides are represented as two sequential nursing events. No nursing event uses a Both side.",
    "Night sleep is classified as an overnight sequence, including early-morning sleep that resumes within 90 minutes of the preceding night segment.",
    "Growth records are converted to native growth events. Temperature and pumping records are preserved as custom events."
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
  output: options[:output],
  summary: options[:summary]
)
