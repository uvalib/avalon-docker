# Pinned: Avalon's solrconfig.xml fails on Solr 9.11.0 ("Unable to initialize ExtractingRequestHandler")
FROM        solr:9.10.1
LABEL       maintainer="Michael B. Klein <michael.klein@northwestern.edu>"
ARG         AVALON_BRANCH=develop
ADD         --chown=solr:solr https://raw.githubusercontent.com/avalonmediasystem/avalon/refs/heads/${AVALON_BRANCH}/solr/conf/schema.xml avalon_conf/
ADD         --chown=solr:solr https://raw.githubusercontent.com/avalonmediasystem/avalon/refs/heads/${AVALON_BRANCH}/solr/conf/solrconfig.xml avalon_conf/
