{
  stdenvNoCC,
  zola,
}:

stdenvNoCC.mkDerivation {
  pname = "pseudo-design-site";
  version = "1.0.0";

  src = ../hosts/mako/site;

  nativeBuildInputs = [ zola ];
  strictDeps = true;

  buildPhase = ''
    runHook preBuild

    zola check --skip-external-links
    zola build

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out"
    cp -R public/. "$out/"

    for required_file in \
      index.html \
      404.html \
      sitemap.xml \
      robots.txt \
      styles.css \
      favicon.png \
      work/index.html \
      work/offline-pki-workflows/index.html \
      work/encrypted-raspberry-pi-infrastructure/index.html \
      work/dogsitting-delivery/index.html \
      fonts/space-grotesk-latin.woff2 \
      fonts/ibm-plex-mono-regular-latin.woff2 \
      fonts/ibm-plex-mono-semibold-latin.woff2 \
      fonts/LICENSE-space-grotesk.txt \
      fonts/LICENSE-ibm-plex-mono.txt
    do
      if [ ! -s "$out/$required_file" ]; then
        echo "missing required site output: $required_file" >&2
        exit 1
      fi
    done

    grep -Fq "Engineering for the hard parts." "$out/index.html"
    grep -Fq "BUILD / REPAIR / SHIP" "$out/index.html"
    grep -Fq "Investigate" "$out/index.html"
    grep -Fq "Deliver" "$out/index.html"
    grep -Fq "Hand off" "$out/index.html"
    grep -Fq "Inherited systems are welcome." "$out/index.html"
    grep -Fq "Frozen assumptions are not." "$out/index.html"
    grep -Fq "Have a problem worth thinking about?" "$out/index.html"
    grep -Fq "mailto:info@pseudo.design?subject=Project%20inquiry" "$out/index.html"
    grep -Fq "https://github.com/PseudoDesign" "$out/index.html"
    grep -Fq "href=#work" "$out/index.html"
    grep -Fq "id=work" "$out/index.html"
    grep -Fq "href=/work/" "$out/index.html"
    grep -Fq "href=/styles.css" "$out/index.html"
    grep -Fq "href=/favicon.png" "$out/index.html"

    grep -Fq \
      "https://github.com/PseudoDesign/nix-pd-pki" \
      "$out/work/offline-pki-workflows/index.html"
    grep -Fq \
      "https://github.com/PseudoDesign/nix-pseudo-design" \
      "$out/work/encrypted-raspberry-pi-infrastructure/index.html"
    grep -Fq \
      "https://github.com/PseudoDesign/dogsitting" \
      "$out/work/dogsitting-delivery/index.html"

    for case_study in \
      work/offline-pki-workflows/index.html \
      work/encrypted-raspberry-pi-infrastructure/index.html \
      work/dogsitting-delivery/index.html
    do
      for section_heading in \
        Problem \
        Constraints \
        Investigation \
        "Delivered System" \
        "Demonstrated Result" \
        Handoff
      do
        grep -Fq "$section_heading" "$out/$case_study"
      done
    done

    if grep -Eq 'https://pseudo\.design/(styles\.css|favicon\.png)' "$out/index.html"; then
      echo "static asset URLs must remain same-origin on the www alias" >&2
      exit 1
    fi

    for metadata_pattern in \
      'rel="?canonical"?' \
      'name="?description"?' \
      'property="?og:title"?' \
      'property="?og:description"?' \
      'property="?og:url"?' \
      'name="?twitter:card"?' \
      'name="?twitter:title"?' \
      'name="?twitter:description"?'
    do
      if ! grep -Eq "$metadata_pattern" "$out/index.html"; then
        echo "missing required homepage metadata: $metadata_pattern" >&2
        exit 1
      fi
    done

    grep -Fq "https://pseudo.design/" "$out/index.html"
    grep -Fq "https://pseudo.design/sitemap.xml" "$out/robots.txt"
    grep -Fq "https://pseudo.design/work/" "$out/sitemap.xml"
    grep -Fq "https://pseudo.design/work/offline-pki-workflows/" "$out/sitemap.xml"
    grep -Fq "https://pseudo.design/work/encrypted-raspberry-pi-infrastructure/" "$out/sitemap.xml"
    grep -Fq "https://pseudo.design/work/dogsitting-delivery/" "$out/sitemap.xml"
    grep -Fq ':focus-visible' "$out/styles.css"
    grep -Fq '@media (prefers-color-scheme: dark)' "$out/styles.css"

    if [ -e "$out/work/example-cross-layer-delivery" ]; then
      echo "draft case study was rendered into the production site" >&2
      exit 1
    fi

    if grep -Rqi --include='*.html' '<script' "$out"; then
      echo "production output contains a script element" >&2
      exit 1
    fi

    if grep -Eqi 'https?://|@import' "$out/styles.css"; then
      echo "production stylesheet contains a remote URL or import" >&2
      exit 1
    fi

    if grep -RqiE \
      --include='*.html' \
      --include='*.css' \
      --include='*.xml' \
      --include='*.txt' \
      'github\.com/ams-tech|(^|[^[:alnum:]_])adam([^[:alnum:]_]|$)' \
      "$out"
    then
      echo "production output contains a legacy organization or personal name" >&2
      exit 1
    fi

    if grep -RqiE \
      --include='*.html' \
      '(^|[^[:alnum:]_])(availability|available now|now booking|seeking work|for hire)([^[:alnum:]_]|$)' \
      "$out"
    then
      echo "production output contains availability messaging" >&2
      exit 1
    fi

    if grep -RqiE \
      --include='*.html' \
      '(^|[^[:alnum:]_])(ai|artificial intelligence|generative ai)([^[:alnum:]_]|$)' \
      "$out"
    then
      echo "production output contains an AI reference" >&2
      exit 1
    fi

    if grep -RqiE \
      --include='*.html' \
      --include='*.css' \
      'google-analytics|googletagmanager|gtag\(|plausible|matomo|posthog|segment\.com|analytics' \
      "$out"
    then
      echo "production output contains analytics or tracking integration text" >&2
      exit 1
    fi

    if grep -RqiE \
      --include='*.html' \
      'property="?og:image|name="?twitter:image' \
      "$out"
    then
      echo "production output unexpectedly contains social preview imagery" >&2
      exit 1
    fi

    runHook postInstall
  '';
}
