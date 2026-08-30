#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "open3"
require "pathname"
require "tmpdir"

NUMBER = /-?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?/

def usd_array(text, declaration)
  match = text.match(/#{Regexp.escape(declaration)}\s*=\s*\[([\s\S]*?)\]/)
  raise "Missing #{declaration}" unless match

  match[1].scan(NUMBER)
end

def load_mesh(path, temporary_directory)
  usda = temporary_directory.join("#{path.basename(".*")}.usda")
  _output, error, status = Open3.capture3(
    "/usr/bin/usdcat",
    path.to_s,
    "-o",
    usda.to_s
  )
  raise "usdcat failed for #{path}: #{error}" unless status.success?

  text = usda.read
  points = usd_array(text, "point3f[] points").map(&:to_f).each_slice(3).to_a
  indices = usd_array(text, "int[] faceVertexIndices").map(&:to_i).each_slice(3).to_a
  normals = begin
    usd_array(text, "normal3f[] normals").map(&:to_f).each_slice(3).to_a
  rescue RuntimeError
    []
  end
  [points, indices, normals]
end

def subtract(lhs, rhs)
  [lhs[0] - rhs[0], lhs[1] - rhs[1], lhs[2] - rhs[2]]
end

def cross(lhs, rhs)
  [
    lhs[1] * rhs[2] - lhs[2] * rhs[1],
    lhs[2] * rhs[0] - lhs[0] * rhs[2],
    lhs[0] * rhs[1] - lhs[1] * rhs[0]
  ]
end

def normalized(vector)
  length = Math.sqrt(vector.sum { |value| value * value })
  return [0.0, 1.0, 0.0] if length.zero?

  vector.map { |value| value / length }
end

def smooth_normals(points, faces)
  normals = Array.new(points.length) { [0.0, 0.0, 0.0] }
  faces.each do |face|
    normal = cross(
      subtract(points[face[1]], points[face[0]]),
      subtract(points[face[2]], points[face[0]])
    )
    face.each do |index|
      3.times { |axis| normals[index][axis] += normal[axis] }
    end
  end
  normals.map { |normal| normalized(normal) }
end

def crop_foot(points, faces, normals, side_sign, upper_y)
  selected_faces = faces.select do |face|
    face.all? do |index|
      point = points[index]
      point[0] * side_sign > 0 && point[1] < upper_y
    end
  end
  raise "Foot crop produced no faces" if selected_faces.empty?

  used_indices = selected_faces.flatten.uniq
  remap = used_indices.each_with_index.to_h
  cropped_points = used_indices.map { |index| points[index] }
  cropped_faces = selected_faces.map { |face| face.map { |index| remap.fetch(index) } }
  cropped_normals = if normals.length == points.length
    used_indices.map { |index| normals[index] }
  else
    smooth_normals(cropped_points, cropped_faces)
  end
  [cropped_points, cropped_faces, cropped_normals]
end

def vectors(values)
  values.map do |value|
    format("(%.8g, %.8g, %.8g)", value[0], value[1], value[2])
  end.join(", ")
end

def write_usdc(points, faces, normals, destination, name, temporary_directory)
  minimum = 3.times.map { |axis| points.map { |point| point[axis] }.min }
  maximum = 3.times.map { |axis| points.map { |point| point[axis] }.max }
  source = temporary_directory.join("#{name}.usda")
  source.write(
    "#usda 1.0\n" \
    "(\n" \
    "    defaultPrim = \"#{name}\"\n" \
    "    metersPerUnit = 1\n" \
    "    upAxis = \"Y\"\n" \
    ")\n\n" \
    "def Xform \"#{name}\"\n" \
    "{\n" \
    "    def Mesh \"Anatomy\"\n" \
    "    {\n" \
    "        float3[] extent = [#{vectors([minimum, maximum])}]\n" \
    "        int[] faceVertexCounts = [#{Array.new(faces.length, 3).join(", ")}]\n" \
    "        int[] faceVertexIndices = [#{faces.flatten.join(", ")}]\n" \
    "        normal3f[] normals = [#{vectors(normals)}] (\n" \
    "            interpolation = \"vertex\"\n" \
    "        )\n" \
    "        point3f[] points = [#{vectors(points)}]\n" \
    "        uniform token subdivisionScheme = \"none\"\n" \
    "    }\n" \
    "}\n"
  )
  _output, error, status = Open3.capture3(
    "/usr/bin/usdcat",
    source.to_s,
    "-o",
    destination.to_s
  )
  raise "usdcat failed for #{destination}: #{error}" unless status.success?

  destination.chmod(0o644)
end

repository = Pathname(__dir__).parent
resources = repository.join("LittleWindows/Resources/BodyAnatomy")
sources = repository.join("Scripts/BodyAnatomySource")

Dir.mktmpdir("littlewindows-foot-detail-") do |directory|
  temporary_directory = Pathname(directory)
  {
    "Female" => -0.475,
    "Male" => -0.532
  }.each do |variant, upper_y|
    inputs = {
      "MuscularSystem" => sources.join("MuscularSystem#{variant}Medium.usdc"),
      "SkeletonSystem" => sources.join("SkeletonSystem#{variant}.usdc"),
      "JointSystem" => sources.join("JointSystem#{variant}.usdc"),
      "NervousSystem" => sources.join("NervousSystem#{variant}.usdc")
    }

    inputs.each do |system, input|
      points, faces, normals = load_mesh(input, temporary_directory)
      { "Left" => 1.0, "Right" => -1.0 }.each do |side, side_sign|
        foot_points, foot_faces, foot_normals = crop_foot(
          points,
          faces,
          normals,
          side_sign,
          upper_y
        )
        name = "Foot#{system}#{variant}#{side}"
        destination = resources.join("#{name}.usdc")
        write_usdc(
          foot_points,
          foot_faces,
          foot_normals,
          destination,
          name,
          temporary_directory
        )
        puts "#{destination}: #{foot_points.length} vertices, #{foot_faces.length} faces"
      end
    end
  end
end
