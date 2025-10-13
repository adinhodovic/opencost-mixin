local mixinUtils = import 'github.com/adinhodovic/mixin-utils/utils.libsonnet';
local g = import 'github.com/grafana/grafonnet/gen/grafonnet-latest/main.libsonnet';
local dashboards = mixinUtils.dashboards;
local util = import 'util.libsonnet';

local dashboard = g.dashboard;
local row = g.panel.row;
local grid = g.util.grid;

local tablePanel = g.panel.table;

// Table
local tbStandardOptions = tablePanel.standardOptions;
local tbQueryOptions = tablePanel.queryOptions;
local tbFieldConfig = tablePanel.fieldConfig;
local tbOverride = tbStandardOptions.override;

{
  local dashboardName = 'opencost-namespace',
  grafanaDashboards+:: {
    ['%s.json' % dashboardName]:

      local defaultVariables = util.variables($._config);

      local variables = [
        defaultVariables.datasource,
        defaultVariables.cluster,
        defaultVariables.job,
        defaultVariables.namespace,
      ];

      local defaultFilters = util.filters($._config);
      local queries = {
        monthlyRamCost: |||
          sum(
            sum(
              container_memory_allocation_bytes{
                %(withNamespace)s
              }
            )
            by (namespace, instance)
            * on(instance) group_left()
            (
              avg(
                node_ram_hourly_cost{
                  %(default)s
                }
              ) by (instance) / (1024 * 1024 * 1024) * 730
            )
          )
        ||| % defaultFilters,

        monthlyCpuCost: |||
          sum(
            sum(
              container_cpu_allocation{
                %(withNamespace)s
              }
            )
            by (namespace, instance)
            * on(instance) group_left()
            (
              avg(
                node_cpu_hourly_cost{
                  %(default)s
                }
              ) by (instance) * 730
            )
          )
        ||| % defaultFilters,

        monthlyPVCost: |||
          sum(
            sum(
              kube_persistentvolume_capacity_bytes{
                %(default)s
              }
              / (1024 * 1024 * 1024)
            ) by (persistentvolume)
            *
            sum(
              pv_hourly_cost{
                %(default)s
              }
            ) by (persistentvolume)
            * on(persistentvolume) group_left(cluster, namespace) (
              label_replace(
                kube_persistentvolumeclaim_info{
                  %(withNamespace)s
                },
                "persistentvolume", "$1",
                "volumename", "(.*)"
              )
            )
          ) * 730
        ||| % defaultFilters,

        monthlyPVNoNilCost: |||
          sum(
            sum(
              kube_persistentvolume_capacity_bytes{
                %(default)s
              }
              / (1024 * 1024 * 1024)
            ) by (persistentvolume)
            *
            sum(
              pv_hourly_cost{
                %(default)s
              }
            ) by (persistentvolume)
            * on(persistentvolume) group_left(cluster, namespace) (
              label_replace(
                kube_persistentvolumeclaim_info{
                  %(withNamespace)s
                },
                "persistentvolume", "$1",
                "volumename", "(.*)"
              )
            ) or vector(0)
          ) * 730
        ||| % defaultFilters,

        monthlyCost: |||
          %s
          +
          %s
          +
          %s
        ||| % [queries.monthlyRamCost, queries.monthlyCpuCost, queries.monthlyPVNoNilCost],
        dailyCost: std.strReplace(queries.monthlyCost, ') * 730', ') * 24'),
        hourlyCost: std.strReplace(queries.monthlyCost, ') * 730', ') * 1'),

        // Keep job label formatting inconsistent due to strReplace
        podMonthlyCost: |||
          topk(10,
            sum(
              (
                sum(
                  container_memory_allocation_bytes{
                    %(cluster)s,
                    %(namespace)s,
                    %(job)s}
                )
                by (instance, pod)
                * on(instance) group_left()
                (
                  avg(
                    node_ram_hourly_cost{
                      %(cluster)s,
                      %(job)s}
                  ) by (instance) / (1024 * 1024 * 1024) * 730
                )
              )
              +
              (
                sum(
                  container_cpu_allocation{
                    %(cluster)s,
                    %(namespace)s,
                    %(job)s}
                )
                by (instance, pod)
                * on(instance) group_left()
                (
                  avg(
                    node_cpu_hourly_cost{
                      %(cluster)s,
                      %(job)s}
                  ) by (instance) * 730)
              )
            ) by (pod)
          )
        ||| % defaultFilters,
        podMonthlyCostOffset7d: std.strReplace(queries.podMonthlyCost, 'job="$job"}', 'job="$job"} offset 7d'),
        podMonthlyCostOffset30d: std.strReplace(queries.podMonthlyCost, 'job="$job"}', 'job="$job"} offset 30d'),

        podMonthlyCostDifference7d: |||
          %s
          /
          %s
          * 100
          - 100
        ||| % [
          queries.podMonthlyCost,
          queries.podMonthlyCostOffset7d,
        ],
        podMonthlyCostDifference30d: |||
          %s
          /
          %s
          * 100
          - 100
        ||| % [
          queries.podMonthlyCost,
          queries.podMonthlyCostOffset30d,
        ],

        containerMonthlyCost: |||
          topk(10,
            sum(
              (
                sum(
                  container_memory_allocation_bytes{
                    %(cluster)s,
                    %(namespace)s,
                    %(job)s}
                )
                by (instance, container)
                * on(instance) group_left()
                (
                  avg(
                    node_ram_hourly_cost{
                      %(cluster)s,
                      %(job)s}
                  ) by (instance) / (1024 * 1024 * 1024) * 730
                )
              )
              +
              (
                sum(
                  container_cpu_allocation{
                    %(cluster)s,
                    %(namespace)s,
                    %(job)s}
                )
                by (instance, container)
                * on(instance) group_left()
                (
                  avg(
                    node_cpu_hourly_cost{
                      %(cluster)s,
                      %(job)s}
                  ) by (instance) * 730
                )
              )
            ) by (container)
          )
        ||| % defaultFilters,
        containerMonthlyCostOffset7d: std.strReplace(queries.containerMonthlyCost, 'job="$job"}', 'job="$job"} offset 7d'),
        containerMonthlyCostOffset30d: std.strReplace(queries.containerMonthlyCost, 'job="$job"}', 'job="$job"} offset 30d'),

        containerMonthlyCostDifference7d: |||
          %s
          /
          %s
          * 100
          - 100
        ||| % [
          queries.containerMonthlyCost,
          queries.containerMonthlyCostOffset7d,
        ],
        containerMonthlyCostDifference30d: |||
          %s
          /
          %s
          * 100
          - 100
        ||| % [
          queries.containerMonthlyCost,
          queries.containerMonthlyCostOffset30d,
        ],

        pvTotalGibByPvQuery: |||
          sum(
            sum(
              kube_persistentvolume_capacity_bytes{
                cluster="$cluster",
                job="$job"
              } / (1024 * 1024 * 1024)
            ) by (persistentvolume)
            * on(persistentvolume) group_left(cluster, namespace)
              label_replace(
                kube_persistentvolumeclaim_info{
                  cluster="$cluster",
                  job="$job",
                  namespace="$namespace"
                },
                "persistentvolume", "$1",
                "volumename", "(.*)"
              )
          ) by (persistentvolume)
        ||| % defaultFilters,
        pvMonthlyCostByPv: std.strReplace(queries.monthlyPVCost, '* 730', 'by (persistentvolume) * 730'),
      };

      local panels = {
        hourlyCostStat:
          dashboards.statPanel(
            'Hourly Cost',
            'currencyUSD',
            queries.hourlyCost,
            graphMode='none',
            decimals=2,
            showPercentChange=true,
            percentChangeColorMode='inverted',
            description='Shows the total daily cost across the cluster.',
          ),

        dailyCostStat:
          dashboards.statPanel(
            'Daily Cost',
            'currencyUSD',
            queries.dailyCost,
            graphMode='none',
            decimals=2,
            showPercentChange=true,
            percentChangeColorMode='inverted',
            description='Shows the total daily cost across the cluster.',
          ),

        monthlyCostStat:
          dashboards.statPanel(
            'Monthly Cost',
            'currencyUSD',
            queries.monthlyCost,
            graphMode='none',
            decimals=2,
            showPercentChange=true,
            percentChangeColorMode='inverted',
            description='Shows the total monthly cost across the cluster.',
          ),

        monthlyRamCostStat:
          dashboards.statPanel(
            'Monthly Ram Cost',
            'currencyUSD',
            queries.monthlyRamCost,
            graphMode='none',
            decimals=2,
            showPercentChange=true,
            percentChangeColorMode='inverted',
            description='Shows the total monthly RAM cost across the cluster.',
          ),

        monthlyCpuCostStat:
          dashboards.statPanel(
            'Monthly CPU Cost',
            'currencyUSD',
            queries.monthlyCpuCost,
            graphMode='none',
            decimals=2,
            showPercentChange=true,
            percentChangeColorMode='inverted',
            description='Shows the total monthly CPU cost across the cluster.',
          ),

        monthlyPVCostStat:
          dashboards.statPanel(
            'Monthly PV Cost',
            'currencyUSD',
            queries.monthlyPVCost,
            graphMode='none',
            decimals=2,
            showPercentChange=true,
            percentChangeColorMode='inverted',
            description='Shows the total monthly Persistent Volume cost across the cluster.',
          ),

        dailyCostTimeSeries:
          dashboards.timeSeriesPanel(
            'Daily Cost',
            'currencyUSD',
            [
              {
                expr: queries.dailyCost,
                legend: 'Daily Cost',
              },
            ],
            description='Shows the total daily cost across the cluster over time.',
          ),

        monthlyCostTimeSeries:
          dashboards.timeSeriesPanel(
            'Monthly Cost',
            'currencyUSD',
            [
              {
                expr: queries.monthlyCost,
                legend: 'Monthly Cost',
              },
            ],
            description='Shows the total monthly cost across the cluster over time.',
          ),

        resourceCostPieChart:
          dashboards.pieChartPanel(
            'Cost by Resource',
            'currencyUSD',
            [
              {
                expr: queries.monthlyCpuCost,
                legend: 'CPU',
              },
              {
                expr: queries.monthlyRamCost,
                legend: 'RAM',
              },
              {
                expr: queries.monthlyPVCost,
                legend: 'PV',
              },
            ],
            description='Shows the cost by resource across the cluster.',
            values=['percent', 'value']
          ),

        podTable:
          dashboards.tablePanel(
            'Pod Monthly Cost',
            'currencyUSD',
            [
              {
                expr: queries.podMonthlyCost,
              },
              {
                expr: queries.podMonthlyCostDifference7d,
              },
              {
                expr: queries.podMonthlyCostDifference30d,
              },
            ],
            sortBy={
              name: 'Total Cost (Today)',
              desc: true,
            },
            transformations=[
              tbQueryOptions.transformation.withId(
                'merge'
              ),
              tbQueryOptions.transformation.withId(
                'organize'
              ) +
              tbQueryOptions.transformation.withOptions(
                {
                  renameByName: {
                    pod: 'Pod',
                    'Value #A': 'Total Cost (Today)',
                    'Value #B': 'Cost Difference (7d)',
                    'Value #C': 'Cost Difference (30d)',
                  },
                  indexByName: {
                    pod: 0,
                    'Value #A': 1,
                    'Value #B': 2,
                    'Value #C': 3,
                  },
                  excludeByName: {
                    Time: true,
                    job: true,
                  },
                }
              ),
            ],
            overrides=[
              tbOverride.byName.new('Cost Difference (7d)') +
              tbOverride.byName.withPropertiesFromOptions(
                tbStandardOptions.withUnit('percent') +
                tbFieldConfig.defaults.custom.withCellOptions(
                  { type: 'color-background' }  // TODO(adinhodovic): Use jsonnet lib
                ) +
                tbStandardOptions.color.withMode('thresholds')
              ),
              tbOverride.byName.new('Cost Difference (30d)') +
              tbOverride.byName.withPropertiesFromOptions(
                tbStandardOptions.withUnit('percent') +
                tbFieldConfig.defaults.custom.withCellOptions(
                  { type: 'color-background' }  // TODO(adinhodovic): Use jsonnet lib
                ) +
                tbStandardOptions.color.withMode('thresholds')
              ),
            ],
            steps=[
              tbStandardOptions.threshold.step.withValue(0) +
              tbStandardOptions.threshold.step.withColor('green'),
              tbStandardOptions.threshold.step.withValue(5) +
              tbStandardOptions.threshold.step.withColor('yellow'),
              tbStandardOptions.threshold.step.withValue(10) +
              tbStandardOptions.threshold.step.withColor('red'),
            ]
          ),

        podCostPieChart:
          dashboards.pieChartPanel(
            'Cost by Pod',
            'currencyUSD',
            [
              {
                expr: queries.podMonthlyCost,
                legend: '{{ pod }}',
              },
            ],
            values=['percent', 'value'],
            description='Shows the cost by pod across the cluster.',
          ),

        containerTable:
          dashboards.tablePanel(
            'Container Monthly Cost',
            'currencyUSD',
            [
              {
                expr: queries.containerMonthlyCost,
              },
              {
                expr: queries.containerMonthlyCostDifference7d,
              },
              {
                expr: queries.containerMonthlyCostDifference30d,
              },
            ],
            sortBy={
              name: 'Total Cost (Today)',
              desc: true,
            },
            transformations=[
              tbQueryOptions.transformation.withId(
                'merge'
              ),
              tbQueryOptions.transformation.withId(
                'organize'
              ) +
              tbQueryOptions.transformation.withOptions(
                {
                  renameByName: {
                    container: 'Container',
                    'Value #A': 'Total Cost (Today)',
                    'Value #B': 'Cost Difference (7d)',
                    'Value #C': 'Cost Difference (30d)',
                  },
                  indexByName: {
                    container: 0,
                    'Value #A': 1,
                    'Value #B': 2,
                    'Value #C': 3,
                  },
                  excludeByName: {
                    Time: true,
                    job: true,
                  },
                }
              ),
            ],
            overrides=[
              tbOverride.byName.new('Cost Difference (7d)') +
              tbOverride.byName.withPropertiesFromOptions(
                tbStandardOptions.withUnit('percent') +
                tbFieldConfig.defaults.custom.withCellOptions(
                  { type: 'color-background' }  // TODO(adinhodovic): Use jsonnet lib
                ) +
                tbStandardOptions.color.withMode('thresholds')
              ),
              tbOverride.byName.new('Cost Difference (30d)') +
              tbOverride.byName.withPropertiesFromOptions(
                tbStandardOptions.withUnit('percent') +
                tbFieldConfig.defaults.custom.withCellOptions(
                  { type: 'color-background' }  // TODO(adinhodovic): Use jsonnet lib
                ) +
                tbStandardOptions.color.withMode('thresholds')
              ),
            ],
            steps=[
              tbStandardOptions.threshold.step.withValue(0) +
              tbStandardOptions.threshold.step.withColor('green'),
              tbStandardOptions.threshold.step.withValue(5) +
              tbStandardOptions.threshold.step.withColor('yellow'),
              tbStandardOptions.threshold.step.withValue(10) +
              tbStandardOptions.threshold.step.withColor('red'),
            ]
          ),

        containerCostPieChart:
          dashboards.pieChartPanel(
            'Cost by Container',
            'currencyUSD',
            [
              {
                expr: queries.containerMonthlyCost,
                legend: '{{ container }}',
              },
            ],
            values=['percent', 'value'],
            description='Shows the cost by container across the cluster.',
          ),

        pvTable:
          dashboards.tablePanel(
            'Persistent Volumes Monthly Cost',
            'decgbytes',
            [
              {
                expr: queries.pvTotalGibByPvQuery,
              },
              {
                expr: queries.pvMonthlyCostByPv,
              },
            ],
            sortBy={
              name: 'Total Cost',
              desc: true,
            },
            transformations=[
              tbQueryOptions.transformation.withId(
                'merge'
              ),
              tbQueryOptions.transformation.withId(
                'organize'
              ) +
              tbQueryOptions.transformation.withOptions(
                {
                  renameByName: {
                    persistentvolume: 'Persistent Volume',
                    'Value #A': 'Total GiB',
                    'Value #B': 'Total Cost',
                  },
                  indexByName: {
                    persistentvolume: 0,
                    'Value #A': 1,
                    'Value #B': 2,
                  },
                  excludeByName: {
                    Time: true,
                    job: true,
                    namespace: true,
                  },
                }
              ),
            ],
            overrides=[
              tbOverride.byName.new('Total Cost') +
              tbOverride.byName.withPropertiesFromOptions(
                tbStandardOptions.withUnit('currencyUSD')
              ),
            ]
          ),

        pvCostPieChart:
          dashboards.pieChartPanel(
            'Cost by Persistent Volume',
            'currencyUSD',
            [
              {
                expr: queries.pvMonthlyCostByPv,
                legend: '{{ persistentvolume }}',
              },
            ],
            values=['percent', 'value'],
            description='Shows the cost by persistent volume across the cluster.',
          ),
      };

      local rows =
        [
          row.new(
            'Summary',
          ) +
          row.gridPos.withX(0) +
          row.gridPos.withY(0) +
          row.gridPos.withW(24) +
          row.gridPos.withH(1),
        ] +
        grid.wrapPanels(
          [
            panels.hourlyCostStat,
            panels.dailyCostStat,
            panels.monthlyCostStat,
            panels.monthlyCpuCostStat,
            panels.monthlyRamCostStat,
            panels.monthlyPVCostStat,
          ],
          panelWidth=4,
          panelHeight=3,
          startY=1
        ) +
        grid.wrapPanels(
          [
            panels.dailyCostTimeSeries,
            panels.monthlyCostTimeSeries,
            panels.resourceCostPieChart,
          ],
          panelWidth=8,
          panelHeight=5,
          startY=4
        ) +
        [
          row.new(
            'Pod Summary',
          ) +
          row.gridPos.withX(0) +
          row.gridPos.withY(9) +
          row.gridPos.withW(24) +
          row.gridPos.withH(1),
          panels.podTable +
          tablePanel.gridPos.withX(0) +
          tablePanel.gridPos.withY(10) +
          tablePanel.gridPos.withW(18) +
          tablePanel.gridPos.withH(10),
          panels.podCostPieChart +
          row.gridPos.withX(18) +
          row.gridPos.withY(10) +
          row.gridPos.withW(6) +
          row.gridPos.withH(10),
        ] +
        [
          row.new(
            'Container Summary',
          ) +
          row.gridPos.withX(0) +
          row.gridPos.withY(20) +
          row.gridPos.withW(24) +
          row.gridPos.withH(1),
          panels.containerTable +
          tablePanel.gridPos.withX(0) +
          tablePanel.gridPos.withY(21) +
          tablePanel.gridPos.withW(18) +
          tablePanel.gridPos.withH(10),
          panels.containerCostPieChart +
          row.gridPos.withX(18) +
          row.gridPos.withY(21) +
          row.gridPos.withW(6) +
          row.gridPos.withH(10),
        ] +
        [
          row.new(
            'PV Summary',
          ) +
          row.gridPos.withX(0) +
          row.gridPos.withY(31) +
          row.gridPos.withW(24) +
          row.gridPos.withH(1),
          panels.pvTable +
          tablePanel.gridPos.withX(0) +
          tablePanel.gridPos.withY(32) +
          tablePanel.gridPos.withW(18) +
          tablePanel.gridPos.withH(10),
          panels.pvCostPieChart +
          row.gridPos.withX(18) +
          row.gridPos.withY(32) +
          row.gridPos.withW(6) +
          row.gridPos.withH(10),
        ];

      mixinUtils.dashboards.bypassDashboardValidation +
      dashboard.new(
        'OpenCost / Namespace',
      ) +
      dashboard.withDescription('A dashboard that monitors OpenCost and focuses on namespace costs. %s' % mixinUtils.dashboards.dashboardDescriptionLink('opencost-mixin', 'https://github.com/adinhodovic/opencost-mixin')) +
      dashboard.withUid($._config.dashboardIds[dashboardName]) +
      dashboard.withTags($._config.tags) +
      dashboard.withTimezone('utc') +
      dashboard.withEditable(false) +
      dashboard.time.withFrom('now-2d') +
      dashboard.time.withTo('now') +
      dashboard.withVariables(variables) +
      dashboard.withLinks(
        mixinUtils.dashboards.dashboardLinks('OpenCost', $._config)
      ) +
      dashboard.withPanels(
        rows
      ) +
      dashboard.withAnnotations(
        mixinUtils.dashboards.annotations($._config, defaultFilters)
      ),
  },
}
