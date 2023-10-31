require "bundler/setup"
Bundler.require
require "base64"

@base_url = "http://localhost:9000"
@session_id = rand().to_s.gsub(".", "")
@quiet_fan = 0 # set in second to let your computer breath
@force_howmany = 0
@settings = {}
@rerender = nil
@prompts = []

#
# Utilitites
#

def log(msg, reason = :info)
  ansi = { error: "\x1b[31;1m", warn: "\x1b[36;1m", info: "\x1b[32;1m" }
  pfx = "#{ansi[reason]}#{reason.to_s.upcase}\x1b[0m"
  puts "[%-8s] %s" % [pfx, msg]
end

def fatal(msg)
  puts "Error : #{msg}"
  exit
end

def prompt_valid?(prompt)
  [:positive, :out_dir] - prompt.keys == []
end

def load_json(filename)
  filename = filename + ".json"
  fatal("file #{filename} not found") unless File.exists?(filename)
  JSON.parse(File.read(filename), { symbolize_names: true })
end

def load_prompts(filename)
  @prompts = []
  prompts = load_json(filename)
  prompts.each_with_index do |prompt, index|
    if prompt_valid?(prompt)
      @prompts << prompt
    else
      puts("missing keys from prompt #{index} - #{filename}")
    end
  end
end

def defaults
  @prompts_common = File.exists?("prompts/common.json") ? load_json("prompts/common") : {}
  Dir.mkdir("images") unless File.exists?("images")
end

def get_option(index)
  if index <= ARGV.size
    ARGV[index]
  else
    fatal "Missing option value"
  end
end

def handle_options
  index = 0
  while index < ARGV.size
    case ARGV[index]
    when "--settings"
      index += 1
      @settings = load_json("settings/#{get_option(index)}")
    when "--howmany"
      index += 1
      @force_howmany = get_option(index).to_i
    when "--rerender"
      index += 1
      @rerender = get_option(index)
    when "--prompts"
      index += 1
      @prompts = load_prompts("prompts/#{get_option(index)}")
    when "--help"
      puts "--settings filename : use a filename.json located in the settings directory"
      puts "--prompts filename  : use prompts from prompts/filename.json"
      puts "--howmany value     : will force howmany no matter the value of the prompt"
      puts "--rerender foo      : will rerender the images from images/foo - a foo.json file must exist in the settings directory."
      puts "                      Each key in this setting file will overwrite the one used when the image have been generated."
      puts "                      foo can take the ALL value, in which case all the images will be rerendered. A all.json file must exist in the settings directory."
      exit
    else
      fatal("Unknow cmd line option #{ARGV[index]}")
    end
    index += 1
  end

  fatal "no settings file provided" if @settings == {} && @rerender == nil
  noeffect = []
  noeffect << "howmany" if @rerender && @force_howmany > 0
  noeffect << "settings" if @rerender && @settings.keys.any?
  if noeffect.size > 0
    puts "There options will have no effect : #{noeffect}"
  end
end

#
# HTTP client
#

def open_connexion
  @conn = Faraday.new(headers: { "Content-Type" => "application/json" })
  await_available()
end

def get(path)
  @conn.get(@base_url + path)
end

def await_available
  count = 0
  while true
    begin
      response = get("/ping?session_id=" + @session_id)
      json = JSON.parse(response.body)
      return if json["status"] == "Online"
    rescue Faraday::ConnectionFailed
    end
    count += 1
    fatal "Unable to connect to easy diffusion server - did you launched it before ?" if count > 5
    sleep 0.5
  end
end

#
# Call renderer
#

def render(settings, outdir, filename = nil)
  start_time = Time.now

  response = @conn.post(@base_url + "/render", settings.to_json)
  json = JSON.parse(response.body, { symbolize_names: true })
  if response.status == 500
    log("An error occured - easy diffusion server said [#{json[:detail]}]", :error)
    return
  end

  task_id = json[:task]
  stream = json[:stream]
  if filename == nil
    img_out_filename = "#{outdir}/#{task_id}.png"
    json_out_filename = "#{outdir}/#{task_id}.json"
  else # rerender
    img_out_filename = "#{outdir}/#{filename}.png"
    json_out_filename = "#{outdir}/#{filename}.json"
  end
  if filename == nil && File.exists?(img_out_filename)
    log("Image file #{img_out_filename} already exists - Skipping", :warn)
    return
  end

  while true
    sleep 2
    response = get(stream)
    if response.body.size > 0
      # Fix bad json format returned by easy diffusion server
      cl_json = "["
      cl_json += response.body.gsub("}{", "},{")
      cl_json += "]"

      json = JSON.parse(cl_json, { symbolize_names: true })
      if json[0][:status] == "failed"
        log("Image generation failed : #{json[0][:detail]}", :error)
        return
      end

      json.each do |h|
        if h.has_key?(:step)
          print "#{h[:step]}/#{h[:total_steps]}\r"
        end
        if h.has_key?(:output)
          b64 = Base64.decode64(h[:output][0][:data][21..]) # remove "data:image/png;base64"
          File.open(img_out_filename, "wb") do |f|
            f.write(b64)
          end
          File.open(json_out_filename, "w") do |f|
            f.write(settings.to_json)
          end
          log("Image generated in #{(Time.now - start_time).round(2)} seconds - written to #{img_out_filename}", :info)
          return
        end
      end
    end
  end
end

#
# Rendering modes -> prompt, rerender, rerender_all
#

def render_prompts(settings)
  settings = settings.clone
  @prompts.each do |prompt|
    if prompt_valid?(prompt)
      pr = prompt.clone
      how_many = @force_howmany == 0 ? pr[:how_many] : @force_howmany
      how_many = 1 unless how_many

      pr[:positive] += "," + @prompts_common[:positive] if @prompts_common[:positive]
      pr[:negative] += "," + @prompts_common[:negative] if @prompts_common[:negative]

      output_dir = "images/#{pr[:out_dir]}"
      log("#{how_many} image(s) will be generated - output to dir #{output_dir}", :info)
      how_many.times do
        Dir.mkdir(output_dir) unless File.exists?(output_dir)
        settings[:seed] = rand(0..4294967295)
        settings[:tiling] = "x"
        settings[:prompt] = pr[:positive]
        settings[:original_prompt] = pr[:positive]
        settings[:negative_prompt] = pr[:negative]
        settings[:session_id] = @session_id
        render(settings, output_dir)
        sleep @quiet_fan
      end
    end
  end
end

def rerender(what, all = false)
  if all
    overwrite_settings = load_json("settings/all")
  else
    overwrite_settings = load_json("settings/#{what}")
  end
  source_dir = "images/#{what}"
  if !File.exists?(source_dir)
    fatal "No directory [#{what}] found in ./images"
  end
  dest_dir = "images/#{what}-#{Time.now.to_i}"
  Dir.mkdir(dest_dir)
  log("Will rerender #{source_dir} in #{dest_dir}", :info)
  Dir["#{source_dir}/**.json"].each do |settings_file|
    settings_file.gsub!(".json", "")
    settings = load_json(settings_file)
    settings.merge!(overwrite_settings)
    render(settings, dest_dir, File.basename(settings_file, ".json"))
    sleep @quiet_fan
  end
end

def rerender_all
  Dir["images/**"].each do |dir|
    next if dir.match(/\-\d+\z/) # skip rerendered dirs
    rerender(File.basename(dir), true)
  end
end

#
# Main
#

defaults()
handle_options()
open_connexion()
case @rerender
when nil
  render_prompts(@settings)
when "all"
  rerender_all
else
  rerender(@rerender)
end
