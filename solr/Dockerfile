FROM        solr:9
LABEL       maintainer="Michael B. Klein <michael.klein@northwestern.edu>"
ARG         AVALON_BRANCH=develop
ADD         --chown=solr:solr https://raw.githubusercontent.com/avalonmediasystem/avalon/refs/heads/${AVALON_BRANCH}/solr/conf/schema.xml avalon_conf/
ADD         --chown=solr:solr https://raw.githubusercontent.com/avalonmediasystem/avalon/refs/heads/${AVALON_BRANCH}/solr/conf/solrconfig.xml avalon_conf/
