local g = import 'github.com/grafana/grafonnet/gen/grafonnet-latest/main.libsonnet';

local dashboard = g.dashboard;

local variable = dashboard.variable;
local datasource = variable.datasource;
local query = variable.query;

{
  filters(config):: {
    local this = self,
    cluster: '%(clusterLabel)s="$cluster"' % config,
    job: 'job="$job"',
    namespace: 'namespace="$namespace"',
    workloadType: 'workload_type=~"$workload_type"',
    workload: 'workload=~"$workload"',

    base: |||
      %(cluster)s,
      %(job)s
    ||| % this,

    default: |||
      %(cluster)s,
      %(job)s
    ||| % this,

    withNamespace: |||
      %(default)s,
      %(namespace)s
    ||| % this,

    withNamespaceWorkload: |||
      %(cluster)s,
      %(namespace)s,
      %(workloadType)s,
      %(workload)s
    ||| % this,
  },

  variables(config):: {
    local this = self,

    local defaultFilters = $.filters(config),

    datasource:
      datasource.new(
        'datasource',
        'prometheus',
      ) +
      datasource.generalOptions.withLabel('Data source') +
      {
        current: {
          selected: true,
          text: config.datasourceName,
          value: config.datasourceName,
        },
      },

    cluster:
      query.new('cluster') +
      query.withDatasourceFromVariable(this.datasource) +
      query.queryTypes.withLabelValues(
        config.clusterLabel,
        'opencost_build_info{}',
      ) +
      query.generalOptions.withLabel('Cluster') +
      query.refresh.onLoad() +
      query.refresh.onTime() +
      query.withSort() +
      (
        if config.showMultiCluster
        then query.generalOptions.showOnDashboard.withLabelAndValue()
        else query.generalOptions.showOnDashboard.withNothing()
      ),

    job:
      query.new(
        'job',
        'label_values(opencost_build_info{%(cluster)s}, job)' % defaultFilters
      ) +
      query.withDatasourceFromVariable(this.datasource) +
      query.withSort() +
      query.generalOptions.withLabel('Job') +
      query.selectionOptions.withMulti(false) +
      query.selectionOptions.withIncludeAll(false) +
      query.refresh.onLoad() +
      query.refresh.onTime(),

    namespace:
      query.new(
        'namespace',
        'label_values(kube_namespace_labels{%(cluster)s, %(job)s}, namespace)' % defaultFilters
      ) +
      query.withDatasourceFromVariable(this.datasource) +
      query.withSort() +
      query.generalOptions.withLabel('Namespace') +
      query.selectionOptions.withMulti(false) +
      query.selectionOptions.withIncludeAll(false) +
      query.refresh.onLoad() +
      query.refresh.onTime(),

    workloadType:
      query.new('workload_type') +
      query.selectionOptions.withIncludeAll() +
      query.withDatasourceFromVariable(this.datasource) +
      query.queryTypes.withLabelValues(
        'workload_type',
        'namespace_workload_pod:kube_pod_owner:relabel{%(clusterLabel)s="$cluster", namespace="$namespace"}' % config,
      ) +
      query.generalOptions.withLabel('Workload Type') +
      query.refresh.onTime() +
      query.generalOptions.showOnDashboard.withLabelAndValue() +
      query.withSort(type='alphabetical'),

    workload:
      query.new('workload') +
      query.selectionOptions.withIncludeAll() +
      query.withDatasourceFromVariable(this.datasource) +
      query.queryTypes.withLabelValues(
        'workload',
        'namespace_workload_pod:kube_pod_owner:relabel{%(clusterLabel)s="$cluster", namespace="$namespace", workload_type=~"$workload_type"}' % config,
      ) +
      query.generalOptions.withLabel('Workload') +
      query.refresh.onTime() +
      query.generalOptions.showOnDashboard.withLabelAndValue() +
      query.withSort(type='alphabetical'),
  },
}
