require 'net/http'
require 'json'
require 'ostruct'

module BHXIVUtils
  module PaperList
    class << self
      def gen_sparql_query(query)
        header = <<~HEREDOC
          prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#>
          prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
          prefix dc: <http://purl.org/dc/terms/>
          prefix bhx: <http://biohackerxiv.org/resource/>
          prefix schema: <https://schema.org/>
        HEREDOC
        header + query
      end

      def sparql_endpoint_url(query)
        base_url = "http://sparql.genenetwork.org/sparql"
        params = "default-graph-uri=&format=application%2Fsparql-results%2Bjson&timeout=0&debug=on&run=+Run+Query+&query=#{URI.encode_www_form_component(gen_sparql_query(query))}"
        "#{base_url}/?#{params}"
      end

      def sparql(query, transform = nil)
        response = Net::HTTP.get_response(URI.parse(sparql_endpoint_url(query)))
        data = JSON.parse(response.body)
        vars = data['head']['vars']
        results = data['results']['bindings']

        results.map do |rec|
          res = {}
          vars.each do |name|
            res[name.to_sym] = rec[name]['value']
          end

          if transform
            transform.call(res)
          else
            res
          end
        end
      end

      def bh_events_list
        events_query = <<~SPARQL_EVENTS
          SELECT  ?url ?name ?descr
          FROM    <https://BioHackrXiv.org/graph>
          WHERE   {
           ?url schema:name ?name .
           ?url schema:description ?descr
          }
        SPARQL_EVENTS
        sparql(events_query)
      end

      def biohackathon_events
        biohackathons = {}
        bh_events_list.each do |rec|
          biohackathons[rec[:name]] = {
            url: rec[:url],
            descr: rec[:descr]
          }
        end
        biohackathons
      end

      def papers_query(bh)
        <<~SPARQL_PAPERS
          SELECT  ?title ?url
          FROM    <https://BioHackrXiv.org/graph>
          WHERE   {
            ?bh schema:name "#{bh}" .
            ?url bhx:Event ?bh ;
              dc:title ?title .
          }
        SPARQL_PAPERS
      end

      def author_query(paper_url)
        <<~SPARQL_AUTHORS
          SELECT  ?author
          FROM    <https://BioHackrXiv.org/graph>
          WHERE   {
            <#{paper_url}> dc:contributor ?author
          }
        SPARQL_AUTHORS
      end

      def bh_papers_list(bh)
        papers = sparql(papers_query(bh), lambda{|paper| OpenStruct.new(paper) })
        papers.each do |paper|
          paper.authors = sparql(author_query(paper.url), lambda{|paper| paper[:author] })
        end
        papers
      end
    end
  end
end
