// 管理员面板 — 主入口

window.__adminDashboard = {
  props: ['routeParams'],
  data() {
    return { surveys: [], loading: true };
  },
  methods: {
    t(key) { return t(key); },
    getSurveyURL,
    statusBadge(s) {
      const map = { draft: 'badge-draft', published: 'badge-published', closed: 'badge-closed' };
      return 'badge ' + (map[s] || '');
    },
    async load() {
      try {
        const res = await fetchAdminSurveys();
        if (res.ok) this.surveys = res.data || [];
      } catch (e) { /* ignore */ }
      this.loading = false;
    },
    goDesign(id) { this.$emit('navigate', 'admin/design/' + id); },
    goSubmissions(id) { this.$emit('navigate', 'admin/submissions/' + id); },
    goResults(id) { this.$emit('navigate', 'admin/results/' + id); },
    goCreate() { this.$emit('navigate', 'admin/surveys'); },
    async toggleStatus(survey) {
      const newStatus = survey.status === 'published' ? 'closed' : 'published';
      try {
        await updateSurveyStatus(survey.id, newStatus);
        await this.load();
      } catch (e) {
        console.error('切换状态失败', e);
        alert(this.t('operation_failed') || '操作失败，请检查权限');
      }
    },
    async deleteOne(survey) {
      if (!confirm(this.t('confirm_delete'))) return;
      try {
        await deleteSurvey(survey.id);
        await this.load();
      } catch (e) {
        console.error('删除问卷失败', e);
        alert(this.t('delete_failed') || '删除失败，请检查权限或网络连接');
      }
    },
    copyURL(survey) {
      const url = getSurveyURL(survey.id);
      navigator.clipboard.writeText(url).then(() => alert(this.t('copied')));
    },
  },
  mounted() { this.load(); },
  template: `
  <div>
    <div class="flex-between mb-4">
      <h2 style="font-size:var(--fs-title)">{{ t('all_surveys') }}</h2>
      <button class="btn" @click="goCreate">{{ t('create') }}</button>
    </div>

    <div v-if="loading" class="text-center mt-6">{{ t('loading') }}</div>

    <div v-else-if="!surveys.length" class="text-center mt-6">
      <div class="alert alert-info">{{ t('no_data') }}</div>
    </div>

    <div v-else>
      <div v-for="s in surveys" :key="s.id" class="card">
        <div class="flex-between" style="margin-bottom:8px">
          <div>
            <span class="card-title" style="font-size:var(--fs-lg)">{{ s.title }}</span>
            <span :class="statusBadge(s.status)" style="margin-left:12px">{{ t(s.status) }}</span>
            <span v-if="s.is_anonymous" class="badge badge-draft" style="margin-left:6px">{{ t('anonymous_badge') }}</span>
          </div>
          <div style="display:flex;gap:6px">
            <button class="btn btn-sm btn-outline" @click="copyURL(s)">{{ t('copy_link') }}</button>
            <button class="btn btn-sm btn-outline" @click="goDesign(s.id)">{{ t('design') }}</button>
            <button class="btn btn-sm btn-outline" @click="goResults(s.id)">{{ t('results') }}</button>
            <button class="btn btn-sm btn-outline" @click="goSubmissions(s.id)">{{ t('submissions_list') }}</button>
            <button class="btn btn-sm btn-outline" @click="toggleStatus(s)">
              {{ s.status === 'published' ? t('close') : t('publish') }}
            </button>
            <button class="btn btn-sm btn-danger" @click="deleteOne(s)">{{ t('delete') }}</button>
          </div>
        </div>
        <div class="card-meta" v-if="s.description">{{ s.description }}</div>
        <div class="card-meta" style="margin-top:4px">
          {{ s.status === 'published' ? '🔗 ' + getSurveyURL(s.id) : '' }}
        </div>
        <div class="card-meta" v-if="s.deadline">
          {{ t('deadline') }}: {{ s.deadline }}
        </div>
      </div>
    </div>
  </div>`
};
