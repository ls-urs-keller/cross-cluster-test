#/bin/bash

set -e
echo "inspired/stolen from https://opensearch.org/docs/latest/security-plugin/access-control/cross-cluster-search/"

echo "9200 -> us-east-1"
echo "9250 -> us-west-2"

echo "adding index templates in both clusters"
for p in 9200 9250; do
curl -s -XPUT -k -H 'Content-Type: application/json' -u 'admin:admin' "https://localhost:${p}/_index_template/payments?pretty" -d '
{
  "index_patterns": [
    "payments-*"
  ],
  "template": {
    "aliases": {
      "payments": {}
    }
  }
}
'
done

echo "adding documents to both subregions"

for ((i=1;i < 11; i ++)); do
curl -s -XPUT -k -H 'Content-Type: application/json' -u 'admin:admin' "https://localhost:9200/payments-2022/_doc/$i" -d '{"desc":"pay'"$i"'", "value": '"$i"', "subregion": "us-east-1"}'
curl -s -XPUT -k -H 'Content-Type: application/json' -u 'admin:admin' "https://localhost:9250/payments-2022/_doc/$i" -d '{"desc":"pay'"$i"'", "value": '"$i"', "subregion": "us-west-2"}'
done

echo
echo "configuring subregions on both sides"
US_EAST_1_IP=$(docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'  opensearch-us-east-1)
US_WEST_2_IP=$(docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'  opensearch-us-west-2)

for p in 9200 9250; do
curl -s -k -XPUT -H 'Content-Type: application/json' -u 'admin:admin' "https://localhost:${p}/_cluster/settings" -d "
{
  \"persistent\": {
    \"cluster.remote\": {
      \"subregion-us-west-2\": {
        \"seeds\": [\"${US_WEST_2_IP}:9300\"]
      },
      \"subregion-us-east-1\": {
        \"seeds\": [\"${US_EAST_1_IP}:9300\"]
      }
    }
  }
}
"
done
echo
echo "searching documents from both sides"

for p in 9200 9250; do
curl -s -XGET -k -u 'admin:admin' -H "Content-Type: application/json" "https://localhost:${p}/subregion-*:payments/_search?pretty" -d '
{
  "query": {
    "match_all": {}
  },
  "aggs": {
    "docs_per_subregion": {
      "terms": {
        "field": "subregion.keyword",
        "size": 10
      },
       "aggs": {
        "value-sum": {
          "sum": {
            "field": "value"
          }
        }
      }
    }
  }
}
'
done


