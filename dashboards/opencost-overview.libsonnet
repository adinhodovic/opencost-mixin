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
local tbPanelOptions = tablePanel.panelOptions;
local tbOverride = tbStandardOptions.override;


{
  local dashboardName = 'opencost-overview',
  grafanaDashboards+:: {
    ['%s.json' % dashboardName]:

      local defaultVariables = util.variables($._config);

      local variables = [
        defaultVariables.datasource,
        defaultVariables.cluster,
        defaultVariables.job,
      ];

      local defaultFilters = util.filters($._config);
      local queries = {
        dailyCost: |||
          sum(
            node_total_hourly_cost{
              %(default)s
            }
          ) * 24
          +
          sum(
            sum(
              kube_persistentvolume_capacity_bytes{
                %(default)s
              } / (1024 * 1024 * 1024)
            ) by (persistentvolume)
            * on(persistentvolume) group_left()
            sum(
              pv_hourly_cost{
                %(default)s
              }
            ) by (persistentvolume)
          ) * 24
        ||| % defaultFilters,
        hourlyCost: std.strReplace(queries.dailyCost, '* 24', ''),
        monthlyCost: std.strReplace(queries.dailyCost, '* 24', '* 730'),

        monthlyRamCost: |||
          sum(
            sum(
              kube_node_status_capacity{
                %(default)s,
                resource="memory",
                unit="byte"
              }
            ) by (node)
            / (1024 * 1024 * 1024)
            * on(node) group_left()
              sum(
                node_ram_hourly_cost{
                  %(default)s
                }
              ) by (node)
            * 730
          )
        ||| % defaultFilters,

        monthlyCpuCost: |||
          sum(
            sum(
              kube_node_status_capacity{
                %(default)s,
                resource="cpu",
                unit="core"
              }
            ) by (node)
            * on(node) group_left()
              sum(
                node_cpu_hourly_cost{
                  %(default)s
                }
              ) by (node)
            * 730
          )
        ||| % defaultFilters,

        monthlyPVCost: |||
          sum(
            sum(
              kube_persistentvolume_capacity_bytes{
                %(default)s
              } / (1024 * 1024 * 1024)
            ) by (persistentvolume)
            * on(persistentvolume) group_left()
              sum(
                pv_hourly_cost{
                  %(default)s
                }
              ) by (persistentvolume)
          ) * 730
        ||| % defaultFilters,

        nodeMonthlyCpuCost: |||
          sum(
            kube_node_status_capacity{
              %(default)s,
              resource="cpu",
              unit="core"
            }
          ) by (node)
          * on(node) group_left(cluster, instance_type, arch)
            sum(
              node_cpu_hourly_cost{
                %(default)s,
              }
            ) by (node, instance_type, arch)
          * 730
        ||| % $._config,

        nodeMonthlyRamCost: |||
          sum(
            kube_node_status_capacity{
              %(default)s,
              resource="memory",
              unit="byte"
            }
          ) by (node)
          / (1024 * 1024 * 1024)
          * on(node) group_left(cluster, instance_type, arch)
            sum(
              node_ram_hourly_cost{
                %(default)s
              }
            ) by (node, instance_type, arch)
          * 730
        ||| % $._config,

        totalCostVariance7d: |||
          (
            avg_over_time(
              sum(
                node_total_hourly_cost{
                  %(default)s
                }
              ) [1d:1h]
            )
            -
            avg_over_time(
              sum(
                node_total_hourly_cost{
                  %(default)s
                }
              ) [7d:1h]
            )
          )
          /
          avg_over_time(
            sum(
              node_total_hourly_cost{
                %(default)s
              }
            ) [7d:1h]
          )
        ||| % $._config,

        totalCostVariance30d: |||
          (
            avg_over_time(
              sum(
                node_total_hourly_cost{
                  %(default)s
                }
              ) [1d:1h]
            )
            -
            avg_over_time(
              sum(
                node_total_hourly_cost{
                  %(default)s
                }
              ) [30d:1h]
            )
          )
          /
          avg_over_time(
            sum(
              node_total_hourly_cost{
                %(default)s
              }
            ) [30d:1h]
          )
        ||| % $._config,

        cpuCostVariance30d: |||
          (
            avg_over_time(
              %s [1d:1h]
            )
            -
            avg_over_time(
              %s [30d:1h]
            )
          )
          /
          avg_over_time(
            %s [30d:1h]
          )
        ||| % [queries.monthlyCpuCost, queries.monthlyCpuCost, queries.monthlyCpuCost],

        ramCostVariance30d: |||
          (
            avg_over_time(
              %s [1d:1h]
            )
            -
            avg_over_time(
              %s [30d:1h]
            )
          )
          /
          avg_over_time(
            %s [30d:1h]
          )
        ||| % [queries.monthlyRamCost, queries.monthlyRamCost, queries.monthlyRamCost],

        pvCostVariance30d: |||
          (
            avg_over_time(
              (%s) [1d:1h]
            )
            -
            avg_over_time(
              (%s) [30d:1h]
            )
          )
          /
          avg_over_time(
            (%s) [30d:1h]
          )
        ||| % [queries.monthlyPVCost, queries.monthlyPVCost, queries.monthlyPVCost],

        // Keep job label formatting inconsistent due to strReplace
        namespaceMonthlyCost: |||
          topk(10,
            sum(
              sum(
                container_memory_allocation_bytes{
                  %(clusterLabel)s="$cluster",
                  job=~"$job"}
              ) by (namespace, instance)
              * on(instance) group_left()
                (
                  node_ram_hourly_cost{
                    %(clusterLabel)s="$cluster",
                    job=~"$job"} / (1024 * 1024 * 1024) * 730
                )
              +
              sum(
                container_cpu_allocation{
                  %(clusterLabel)s="$cluster",
                  job=~"$job"}
              ) by (namespace, instance)
              * on(instance) group_left()
                (
                  node_cpu_hourly_cost{
                    %(clusterLabel)s="$cluster",
                    job=~"$job"} * 730
                )
            ) by (namespace)
          )
        ||| % defaultFilters,

        monthlyCostOffset7d: std.strReplace(queries.namespaceMonthlyCost, 'job=~"$job"}', 'job=~"$job"} offset 7d'),
        monthlyCostOffset30d: std.strReplace(queries.namespaceMonthlyCost, 'job=~"$job"}', 'job=~"$job"} offset 30d'),

        costDifference7d: |||
          %s
          /
          %s
          * 100
          - 100
        ||| % [queries.namespaceMonthlyCost, queries.monthlyCostOffset7d],
        costDifference30d: |||
          %s
          /
          %s
          * 100
          - 100
        ||| % [queries.namespaceMonthlyCost, queries.monthlyCostOffset30d],

        instanceTypeCost: |||
          topk(10,
            sum(
              node_total_hourly_cost{
                %(default)s
              }
            ) by (instance_type) * 730
          )
        ||| % defaultFilters,

        nodeTotalCost: |||
          sum(
            node_total_hourly_cost{
              %(default)s
            }
          ) by (node, instance_type, arch)
          * 730
        ||| % defaultFilters,

        pvTotalGib: |||
          sum(
            kube_persistentvolume_capacity_bytes{
              %(default)s
            }
            / 1024 / 1024 / 1024
          ) by (persistentvolume)
        ||| % defaultFilters,

        pvMonthlyCost: |||
          sum(
            kube_persistentvolume_capacity_bytes{
              %(default)s
            }
            / 1024 / 1024 / 1024
          ) by (persistentvolume)
          *
          sum(
            pv_hourly_cost{
              %(default)s
            }
            * 730
          ) by (persistentvolume)
        ||| % defaultFilters,
      };

      local panels = {
        dailyCostStat: dashboards.statPanel(
          'Daily Cost',
          'currencyUSD',
          queries.dailyCost,
          description='Shows the total daily cost across the cluster.',
        ),

        hourlyCostStat: dashboards.statPanel(
          'Hourly Cost',
          'currencyUSD',
          queries.hourlyCost,
          description='Shows the total hourly cost across the cluster.',
        ),

        monthlyCostStat: dashboards.statPanel(
          'Monthly Cost',
          'currencyUSD',
          queries.monthlyCost,
          description='Shows the total monthly cost across the cluster.',
        ),

        monthlyRamCostStat: dashboards.statPanel(
          'Monthly Ram Cost',
          'currencyUSD',
          queries.monthlyRamCost,
          description='Shows the total monthly RAM cost across the cluster.',
        ),

        monthlyCpuCostStat: dashboards.statPanel(
          'Monthly CPU Cost',
          'currencyUSD',
          queries.monthlyCpuCost,
          description='Shows the total monthly CPU cost across the cluster.',
        ),

        monthlyPVCostStat: dashboards.statPanel(
          'Monthly PV Cost',
          'currencyUSD',
          queries.monthlyPVCost,
          description='Shows the total monthly Persistent Volume cost across the cluster.',
        ),

        hourCostTimeSeries:
          dashboards.timeSeriesPanel(
            'Hourly Cost',
            'currencyUSD',
            queries.hourlyCost,
            'Hourly Cost',
            description='Shows the hourly cost across the cluster.',
          ),

        dailyCostTimeSeries:
          dashboards.timeSeriesPanel(
            'Daily Cost',
            'currencyUSD',
            queries.dailyCost,
            'Daily Cost',
            description='Shows the daily cost across the cluster.',
          ),

        monthlyCostTimeSeries:
          dashboards.timeSeriesPanel(
            'Monthly Cost',
            'currencyUSD',
            queries.monthlyCost,
            'Monthly Cost',
            description='Shows the monthly cost across the cluster.',
          ),

        totalCostVarianceTimeSeries:
          dashboards.timeSeriesPanel(
            'Total Cost Variance',
            'percentunit',
            [
              {
                expr: queries.totalCostVariance7d,
                legend: 'Current hourly cost vs. 7-day average',
              },
              {
                expr: queries.totalCostVariance30d,
                legend: 'Current hourly cost vs. 30-day average',
              },
            ],
            description='Shows the total cost variance across the cluster.',
          ),

        resourceCostPieChartPanel:
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
          ),

        namespaceCostPieChartPanel:
          dashboards.pieChartPanel(
            'Cost by Namespace',
            'currencyUSD',
            queries.namespaceMonthlyCost,
            '{{ namespace }}',
            description='Shows the cost by namespace across the cluster.',
          ),

        instanceTypeCostPieChartPanel:
          dashboards.pieChartPanel(
            'Cost by Instance Type',
            'currencyUSD',
            queries.instanceTypeCost,
            '{{ instance_type }}',
            description='Shows the cost by instance type across the cluster.',
          ),

        nodeTable:
          dashboards.tablePanel(
            'Nodes Monthly Cost',
            'currencyUSD',
            [
              {
                expr: queries.nodeMonthlyCpuCost,
              },
              {
                expr: queries.nodeMonthlyRamCost,
              },
              {
                expr: queries.nodeTotalCost,
              },
            ],
            description='Shows the monthly cost by node across the cluster.',
            sortBy={
              name: 'Total Cost',
              desc: false,
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
                    node: 'Node',
                    instance_type: 'Instance Type',
                    arch: 'Architecture',
                    'Value #A': 'CPU Cost',
                    'Value #B': 'RAM Cost',
                    'Value #C': 'Total Cost',
                  },
                  indexByName: {
                    node: 0,
                    instance_type: 1,
                    arch: 2,
                    'Value #A': 3,
                    'Value #B': 4,
                    'Value #C': 5,
                  },
                  excludeByName: {
                    Time: true,
                    job: true,
                  },
                }
              ),
            ]
          ),

        pvTable:
          dashboards.tablePanel(
            'Persistent Volumes Monthly Cost',
            'decgbytes',
            [
              {
                expr: queries.pvTotalGib,
              },
              {
                expr: queries.pvMonthlyCost,
              },
            ],
            description='Shows the monthly cost by persistent volume across the cluster.',
            sortBy={
              name: 'Total Cost',
              desc: false,
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

        namespaceTable:
          dashboards.tablePanel(
            'Namespace Monthly Cost',
            'currencyUSD',
            [
              {
                expr: queries.namespaceMonthlyCost,
              },
              {
                expr: queries.monthlyCostOffset7d,
              },
              {
                expr: queries.monthlyCostOffset30d,
              },
            ],
            description='Shows the monthly cost by namespace across the cluster.',
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
                    namespace: 'Namespace',
                    'Value #A': 'Total Cost (Today)',
                    'Value #B': 'Cost Difference (7d)',
                    'Value #C': 'Cost Difference (30d)',
                  },
                  indexByName: {
                    namespace: 0,
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
              tbOverride.byName.new('Namespace') +
              tbOverride.byName.withPropertiesFromOptions(
                tbStandardOptions.withLinks(
                  tbPanelOptions.link.withTitle('Go To Namespace') +
                  tbPanelOptions.link.withType('dashboard') +
                  tbPanelOptions.link.withUrl(
                    '/d/%s/opencost-namespace?var-job=$job&var-namespace=${__data.fields.Namespace}' % $._config.openCostNamespaceDashboardUid
                  ) +
                  tbPanelOptions.link.withTargetBlank(true)
                )
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
      };

      local rows =
        [
          row.new('Cluster Summary') +
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
            panels.hourCostTimeSeries,
            panels.dailyCostTimeSeries,
            panels.monthlyCostTimeSeries,
          ],
          panelWidth=8,
          panelHeight=5,
          startY=5
        ) +
        grid.wrapPanels(
          [
            panels.resourceCostPieChartPanel,
            panels.namespaceCostPieChartPanel,
            panels.instanceTypeCostPieChartPanel,
          ],
          panelWidth=8,
          panelHeight=5,
          startY=10
        ) +
        grid.wrapPanels(
          [
            panels.totalCostVarianceTimeSeries,
          ],
          panelWidth=12,
          panelHeight=5,
          startY=15
        ) +
        [
          row.new('Cloud Resources') +
          row.gridPos.withX(0) +
          row.gridPos.withY(20) +
          row.gridPos.withW(24) +
          row.gridPos.withH(1),
        ] +
        [
          panels.nodeTable +
          tablePanel.gridPos.withX(0) +
          tablePanel.gridPos.withY(21) +
          tablePanel.gridPos.withW(16) +
          tablePanel.gridPos.withH(10),
          panels.pvTable +
          tablePanel.gridPos.withX(16) +
          tablePanel.gridPos.withY(21) +
          tablePanel.gridPos.withW(8) +
          tablePanel.gridPos.withH(10),
          row.new('Namespace Summary') +
          row.gridPos.withX(0) +
          row.gridPos.withY(31) +
          row.gridPos.withW(24) +
          row.gridPos.withH(1),
          panels.namespaceTable +
          tablePanel.gridPos.withX(0) +
          tablePanel.gridPos.withY(32) +
          tablePanel.gridPos.withW(24) +
          tablePanel.gridPos.withH(12),
        ];

      mixinUtils.dashboards.bypassDashboardValidation +
      dashboard.new(
        'OpenCost / Overview',
      ) +
      dashboard.withDescription('A dashboard that monitors OpenCost and focuses on giving a overview for OpenCost. It is created using the [opencost-mixin](https://github.com/adinhodovic/opencost-mixin).') +
      dashboard.withDescription('A dashboard that monitors OpenCost and focuses on giving a overview for OpenCost. %s' % mixinUtils.dashboards.dashboardDescriptionLink('opencost-mixin', 'https://github.com/adinhodovic/opencost-mixin')) +
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
