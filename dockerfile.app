FROM ruby:3.0.2

ENV PANDOC_VERSION="2.16.1"

RUN wget --output-document="/pandoc-${PANDOC_VERSION}-linux-amd64.tar.gz" "https://github.com/jgm/pandoc/releases/download/${PANDOC_VERSION}/pandoc-${PANDOC_VERSION}-linux-amd64.tar.gz" && \
    tar xf "pandoc-${PANDOC_VERSION}-linux-amd64.tar.gz" && \
    ln -s "/pandoc-${PANDOC_VERSION}/bin/pandoc" "/usr/local/bin"

RUN apt update -y && apt install -y \
    librsvg2-bin=2.50.3+dfsg-1 \
    texlive-bibtex-extra=2020.20210202-3 \
    texlive-latex-base=2020.20210202-3 \
    texlive-latex-extra=2020.20210202-3

COPY . /app/
WORKDIR /app
RUN bundle install
EXPOSE 9292

WORKDIR /

# Change the date env value to re-download the updated gen-pdf script
ENV UPDATE_DATE="20230630-01"

RUN git clone "https://github.com/biohackrxiv/bhxiv-gen-pdf" --depth 1 && chmod +x /bhxiv-gen-pdf/bin/gen-pdf
ENV PATH $PATH:/bhxiv-gen-pdf/bin

WORKDIR /app
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
