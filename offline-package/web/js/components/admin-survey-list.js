// 管理员 — 问卷列表（创建/编辑问卷信息）

window.__adminSurveyList = {
  props: ['routeParams'],
  data() {
    return {
      surveys: [],
      loading: true,
      showForm: false,
      editSurvey: null,
      formTitle: '',
      formDesc: '',
      formAnonymous: false,
      formDeadline: '',
      showSubmissions: null,
      submissions: [],
      showAdmins: false,
      adminList: [],
      newAdminName: '',
    };
  },
  methods: {
    t(key) { return t(key); },
    getSurveyURL,
    statusBadge(s) {
      const map = { draft: 'badge-draft', published: 'badge-published', closed: 'badge-closed' };
      return 'badge ' + (map[s] || '');
    },
    async loadSurveys() {
      try {
        const res = await fetchAdminSurveys();
        if (res.ok) this.surveys = res.data || [];
      } catch (e) {
        console.error('加载问卷列表失败', e);
      }
      this.loading = false;
    },
    goDesign(id) { this.$emit('navigate', 'admin/design/' + id); },
    goResults(id) { this.$emit('navigate', 'admin/results/' + id); },
    goDashboard() { this.$emit('navigate', 'admin'); },
    openCreate() {
      this.editSurvey = null;
      this.formTitle = '';
      this.formDesc = '';
      this.formAnonymous = false;
      this.formDeadline = '';
      this.showForm = true;
    },
    openEdit(s) {
      this.editSurvey = s;
      this.formTitle = s.title;
      this.formDesc = s.description;
      this.formAnonymous = s.is_anonymous;
      this.formDeadline = s.deadline || '';
      this.showForm = true;
    },
    async saveForm() {
      if (!this.formTitle.trim()) { alert(this.t('empty_title')); return; }
      const data = {
        title: this.formTitle,
        description: this.formDesc,
        is_anonymous: this.formAnonymous,
        deadline: this.formDeadline,
      };
      try {
        if (this.editSurvey) {
          await updateSurvey(this.editSurvey.id, data);
        } else {
          const res = await createSurvey(data);
          if (res.ok && res.data) {
            this.showForm = false;
            this.$emit('navigate', 'admin/design/' + res.data.id);
            return;
          }
        }
      } catch (e) {
        console.error('保存问卷失败', e);
        alert(this.t('save_failed') || '保存失败，请检查权限或网络连接');
      }
      this.showForm = false;
      await this.loadSurveys();
    },
    async deleteOne(s) {
      if (!confirm(this.t('confirm_delete'))) return;
      try {
        await deleteSurvey(s.id);
        await this.loadSurveys();
      } catch (e) {
        console.error('删除问卷失败', e);
        alert(this.t('delete_failed') || '删除失败，请检查权限或网络连接');
      }
    },
    async loadSubmissions(survey) {
      try {
        const res = await fetchSubmissions(survey.id);
        if (res.ok) this.submissions = res.data || [];
      } catch (e) {
        console.error('加载提交记录失败', e);
      }
      this.showSubmissions = survey;
    },
    async exportOne(survey) {
      const blob = await exportExcel(survey.id);
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = 'survey_' + survey.title + '.xlsx';
      a.click();
      URL.revokeObjectURL(url);
    },
    copyURL(survey) {
      const url = getSurveyURL(survey.id);
      copyToClipboard(url); alert(this.t('copied'));
    },
    async loadAdmins() {
      this.showAdmins = true;
      try {
        const res = await fetchAdmins();
        if (res.ok) this.adminList = res.data || [];
      } catch (e) {
        console.error('加载管理员列表失败', e);
      }
    },
    async addAdminUser() {
      if (!this.newAdminName.trim()) return;
      try {
        await addAdmin(this.newAdminName);
        this.newAdminName = '';
        await this.loadAdmins();
      } catch (e) {
        console.error('添加管理员失败', e);
        alert(this.t('add_admin_failed') || '添加管理员失败，请检查权限');
      }
    },
    async removeAdminUser(id) {
      try {
        await removeAdmin(id);
        await this.loadAdmins();
      } catch (e) {
        console.error('删除管理员失败', e);
        alert(this.t('remove_admin_failed') || '删除管理员失败，请检查权限');
      }
    },
  },
  mounted() { this.loadSurveys(); },
  template: `
  <div>
    <div class="flex-between mb-4">
      <h2 style="font-size:var(--fs-title)">
        <a href="#" @click.prevent="goDashboard" style="color:var(--color-muted);text-decoration:none;font-size:var(--fs-lg)">←</a>
        {{ t('all_surveys') }}
      </h2>
      <div style="display:flex;gap:8px">
        <button class="btn btn-sm btn-outline" @click="loadAdmins">{{ t('admin_users') }}</button>
        <button class="btn" @click="openCreate">{{ t('create') }}</button>
      </div>
    </div>

    <!-- 管理员列表 -->
    <div v-if="showAdmins" class="card mb-4">
      <div class="flex-between mb-4">
        <h3>{{ t('admin_users') }}</h3>
        <button class="btn btn-sm btn-outline" @click="showAdmins=false">{{ t('cancel') }}</button>
      </div>
      <div v-for="a in adminList" :key="a.id" class="flex-between" style="padding:8px 0;border-bottom:1px solid var(--color-border)">
        <span>{{ a.username }}</span>
        <button class="btn btn-sm btn-danger" @click="removeAdminUser(a.id)">{{ t('delete') }}</button>
      </div>
      <div class="flex mt-4 gap-2">
        <input class="input" v-model="newAdminName" :placeholder="t('admin_username')" style="flex:1" />
        <button class="btn btn-sm" @click="addAdminUser">{{ t('add_admin') }}</button>
      </div>
    </div>

    <!-- 表单 -->
    <div v-if="showForm" class="card mb-4">
      <div class="form-group">
        <label class="form-label">{{ t('survey_title') }}</label>
        <input class="input" v-model="formTitle" autofocus />
      </div>
      <div class="form-group">
        <label class="form-label">{{ t('survey_desc') }}</label>
        <textarea class="textarea" v-model="formDesc" rows="3"></textarea>
      </div>
      <div class="form-group">
        <label style="display:flex;align-items:center;gap:8px;cursor:pointer">
          <input type="checkbox" v-model="formAnonymous" style="width:18px;height:18px" />
          {{ t('anonymous') }}
        </label>
      </div>
      <div class="form-group">
        <label class="form-label">{{ t('deadline') }}</label>
        <input class="input" type="datetime-local" v-model="formDeadline" />
        <div class="card-meta mt-2">{{ t('no_deadline') }}</div>
      </div>
      <div style="display:flex;gap:8px">
        <button class="btn" @click="saveForm">{{ t('save') }}</button>
        <button class="btn btn-outline" @click="showForm=false">{{ t('cancel') }}</button>
      </div>
    </div>

    <!-- 提交记录 -->
    <div v-if="showSubmissions" class="card mb-4">
      <div class="flex-between mb-4">
        <h3>{{ showSubmissions.title }} — {{ t('submissions_list') }}</h3>
        <div style="display:flex;gap:8px">
          <button class="btn btn-sm btn-outline" @click="exportOne(showSubmissions)">{{ t('export') }}</button>
          <button class="btn btn-sm btn-outline" @click="showSubmissions=null">{{ t('cancel') }}</button>
        </div>
      </div>
      <div v-if="!submissions.length" class="text-center">{{ t('no_data') }}</div>
      <div v-else class="table-wrap">
        <table>
          <thead>
            <tr>
              <th>#</th>
              <th>{{ t('username') }}</th>
              <th>{{ t('submitted_at') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="(s, i) in submissions" :key="s.id">
              <td>{{ i + 1 }}</td>
              <td>{{ s.username }}</td>
              <td>{{ s.submitted_at }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <!-- 问卷列表 -->
    <div v-if="loading" class="text-center mt-6">{{ t('loading') }}</div>
    <div v-else-if="!surveys.length" class="text-center mt-6">
      <div class="alert alert-info">{{ t('no_data') }}</div>
    </div>
    <div v-else>
      <div v-for="s in surveys" :key="s.id" class="card">
        <div class="flex-between" style="margin-bottom:8px">
          <div>
            <span style="font-size:var(--fs-lg);font-weight:600">{{ s.title }}</span>
            <span :class="statusBadge(s.status)" style="margin-left:12px">{{ t(s.status) }}</span>
            <span v-if="s.is_anonymous" class="badge badge-draft" style="margin-left:6px">{{ t('anonymous_badge') }}</span>
          </div>
          <div style="display:flex;gap:6px;flex-wrap:wrap">
            <button class="btn btn-sm btn-outline" @click="openEdit(s)">{{ t('edit') }}</button>
            <button class="btn btn-sm btn-outline" @click="goDesign(s.id)">{{ t('design') }}</button>
            <button class="btn btn-sm btn-outline" @click="goResults(s.id)">{{ t('results') }}</button>
            <button class="btn btn-sm btn-outline" @click="loadSubmissions(s)">{{ t('submissions_list') }}</button>
            <button class="btn btn-sm btn-outline" @click="exportOne(s)">{{ t('export') }}</button>
            <button class="btn btn-sm btn-outline" @click="copyURL(s)">{{ t('copy_link') }}</button>
            <button class="btn btn-sm btn-danger" @click="deleteOne(s)">{{ t('delete') }}</button>
          </div>
        </div>
        <div class="card-meta" v-if="s.description">{{ s.description }}</div>
        <div class="card-meta" v-if="s.deadline">{{ t('deadline') }}: {{ s.deadline }}</div>
        <div class="card-meta mt-2" v-if="s.status === 'published'">
          <code style="font-size:14px;word-break:break-all">{{ getSurveyURL(s.id) }}</code>
        </div>
      </div>
    </div>
  </div>`
};
