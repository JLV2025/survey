// 统计页 — ECharts 饼图 + 30s 轮询

window.__surveyStats = {
  props: ['routeParams'],
  data() {
    return {
      stats: null,
      loading: true,
      error: '',
      timer: null,
    };
  },
  methods: {
    t(key) { return t(key); },
    async loadStats() {
      try {
        const id = this.routeParams.id;
        if (!id) return;
        const res = await fetchStats(id);
        if (res.ok && res.data) {
          this.stats = res.data;
          this.error = '';
          this.$nextTick(() => this.renderCharts());
        } else {
          this.error = res.message || this.t('server_error');
        }
      } catch (e) {
        // 保持现有数据不变
      }
      this.loading = false;
    },
    renderCharts() {
      if (!this.stats || !this.stats.questions) return;

      this.stats.questions.forEach((q, i) => {
        if (q.type !== 'single' && q.type !== 'multiple') return;
        if (!q.option_counts || !q.option_counts.length) return;

        const dom = document.getElementById('chart_' + i);
        if (!dom) return;
        const chart = echarts.init(dom);
        chart.setOption({
          tooltip: { trigger: 'item' },
          legend: {
            orient: 'vertical',
            left: 'left',
            top: 'middle',
            textStyle: { fontSize: 16 },
          },
          series: [{
            name: q.title,
            type: 'pie',
            radius: ['40%', '70%'],
            center: ['55%', '50%'],
            avoidLabelOverlap: false,
            label: { show: false },
            emphasis: {
              label: { show: true, fontSize: 20, fontWeight: 'bold' },
            },
            data: q.option_counts.map(o => ({
              name: o.content,
              value: o.count,
            })),
          }],
        });
      });
    },
  },
  mounted() {
    this.loadStats();
    this.timer = setInterval(() => this.loadStats(), 30000);
  },
  beforeUnmount() {
    if (this.timer) clearInterval(this.timer);
  },
  template: `
  <div>
    <div v-if="loading" class="text-center mt-6">{{ t('loading') }}</div>

    <div v-else-if="error" class="text-center mt-6">
      <div class="alert alert-warn">{{ error }}</div>
    </div>

    <div v-else-if="stats">
      <div class="stats-header">
        <h2 style="font-size:var(--fs-title)">{{ stats.survey_title }}</h2>
        <p class="stats-total">{{ t('total_submissions') }}: {{ stats.total_submissions }}</p>
      </div>

      <div v-if="stats.total_submissions === 0" class="text-center">
        <div class="alert alert-info">{{ t('no_data') }}</div>
      </div>

      <div v-else>
        <div v-for="(q, i) in stats.questions" :key="q.question_id" class="card">
          <div class="question-title">{{ q.title }}</div>

          <!-- 选择题：饼图 -->
          <div v-if="q.type === 'single' || q.type === 'multiple'">
            <div v-if="q.option_counts && q.option_counts.length" class="chart-container" :id="'chart_' + i"></div>
            <div v-else class="alert alert-info">{{ t('no_data') }}</div>
          </div>

          <!-- 填空题：文本列表 -->
          <div v-if="q.type === 'text' || q.type === 'textarea'">
            <div v-if="q.text_answers && q.text_answers.length">
              <div v-for="(txt, j) in q.text_answers" :key="j"
                style="padding:8px 0;border-bottom:1px solid var(--color-border);font-size:var(--fs-base)">
                {{ txt }}
              </div>
            </div>
            <div v-else class="alert alert-info">{{ t('no_data') }}</div>
          </div>
        </div>
      </div>
    </div>
  </div>`
};
