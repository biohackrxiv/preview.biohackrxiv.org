$LOAD_PATH << __dir__

require 'sinatra'
# require 'sinatra/json'
require 'slim'
require 'securerandom'
require 'lib/list'
require 'logger'

$logger = Logger.new(STDOUT)
$logger.level = Logger::DEBUG

configure {
  set :server, :puma
  set :show_exceptions, true
  set :environment, :development
  set :logging, :true
}

class CommandError < StandardError
end

def system_log(cmd)
  $logger.debug("Invoking: #{cmd}\n")
  result = `#{cmd} 2>&1`
  status = $?.exitstatus
  result2 = result.force_encoding('utf-8')
  $logger.debug(result2)
  if status!=0
    raise CommandError, "Failed to run command: "+result2
  end
end

# Run tests on startup
system_log("cp -vau /bhxiv-gen-pdf/example /tmp/")
system_log("cd /bhxiv-gen-pdf && ruby ./bin/gen-pdf --debug /tmp/example/logic Japan2019")

class BHXIV < Sinatra::Base
  helpers do
    def create_workdir(id)
      workdir = "/tmp/#{id}"
      FileUtils.mkdir(workdir)
      workdir
    end

    def stage_zipfile(id, zipfile)
      workdir = create_workdir(id)
      filepath = zipfile[:tempfile].path
      system_log("unzip #{filepath} -d #{workdir}")
    end

    def stage_gitrepo(id, git_url)
      workdir = create_workdir(id)
      system_log("git clone --depth 1 -c core.askPass=echo #{git_url} #{workdir}/#{File.basename(git_url)}")
    end

    def create_outdir(id)
      outdir_path = File.dirname(__FILE__) + "/public/papers/#{id}"
      FileUtils.mkdir_p(outdir_path)
      outdir_path
    end

    def gen_pdf(id, journal, git_url = nil)
      # Find paper.md
      glob = "/tmp/#{id}/**/paper.md"
      $logger.debug(glob)
      files = Dir.glob(glob)
      if files.size < 1
        raise CommandError, "Can not find a paper.md in directory structure!"
      end
      paper_dir = File.dirname(files.first)
      # Prepare output dir
      outdir = create_outdir(id)
      pdf_path = "#{outdir}/paper.pdf"
      # Generate
      system_log("gen-pdf #{paper_dir} #{journal} #{pdf_path} #{git_url}")
      # Return pdf_path      "/papers/#{id}/paper.pdf"
      "/papers/#{id}/paper.pdf"
    end
  end

  configure do
    set :root, File.dirname(__FILE__)
    set :protection, :except => [:json_csrf]

    set :events, BHXIVUtils::PaperList.biohackathon_events()
    set :all_papers, BHXIVUtils::PaperList.all_papers(settings.events)
    set :all_papers_expanded, BHXIVUtils::PaperList.expand_authors(settings.all_papers)

    set :count_events, settings.events.length
    set :count_papers, settings.all_papers.map { |k,v| v }.flatten.length
    set :count_authors, BHXIVUtils::PaperList.count_authors()
  end

  error CommandError do
    # 'Sorry there was a nasty error - ' + env['sinatra.error'].message
    @error_msg = env['sinatra.error'].message
    slim :error
  end

  error do
    'Server error: ' + env['sinatra.error'].message
  end

  get '/' do
    @biohackathons = settings.events
    @papers = settings.all_papers
    @count_events = settings.count_events
    @count_papers = settings.count_papers
    @count_authors = settings.count_authors
    slim :index
  end

  post '/gen-pdf' do
    # Get form parameters
    $logger.debug(params)
    journal = params[:journal]
    git_url = params[:repository]
    zipfile = params[:zipfile]

    pdf_path = if journal
                 id = SecureRandom.uuid
                 if zipfile
                   stage_zipfile(id, zipfile)
                   gen_pdf(id, journal)
                 elsif git_url
                   stage_gitrepo(id, git_url)
                   gen_pdf(id, journal, git_url)
                 end
               end

    if pdf_path
      content_type 'application/pdf' # not sure this works before a redirect, but it does not hurt
      redirect pdf_path
    else
      status 500
    end
  end

  get '/list.json' do
    content_type :json
    h = BHXIVUtils::PaperList.to_h(settings.events, settings.all_papers_expanded)
    JSON(h)
  end

  get '/list' do
    @biohackathons = settings.events
    @papers = settings.all_papers
    # expand authors (we could have done this more lazily)
    @papers = settings.all_papers_expanded
    @count_events = settings.count_events
    @count_papers = settings.count_papers
    @count_authors = settings.count_authors
    slim :list
  end
end
