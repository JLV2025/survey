// 管理员用户管理 — 独立页面

window.__adminUsers = {
  props: ['routeParams'],
  data() {
    return {
      adminList: [],
      loading: true,
      newAdminName: '',
    };
  },
  methods: {
    t(key) { return t(key); },
    goBack() { this.$emit('navigate', 'admin'); },
    async loadAdmins() {
      this.loading = true;
      try {
        const res = await fetchAdmins();
        if (res.ok) this.adminList = res.data || [];
      } catch (e) {
        console.error('加载管理员列表失败', e);
      }
      this.loading = false;
    },
    async addAdminUser() {
      if (!this.newAdminName.trim()) return;
      try {
        const r = await addAdmin(this.newAdminName);
        if (!r.ok) { alert(r.message || this.t('add_admin_failed') || '添加管理员失败'); return; }
        this.newAdminName = '';
        await this.loadAdmins();
      } catch (e) {
        console.error('添加管理员失败', e);
        alert(this.t('add_admin_failed') || '添加管理员失败，请检查权限');
      }
    },
    async removeAdminUser(id) {
      if (!confirm(this.t('confirm_delete'))) return;
      try {
        const r = await removeAdmin(id);
        if (!r.ok) { alert(r.message || this.t('remove_admin_failed') || '删除管理员失败'); return; }
        await this.loadAdmins();
      } catch (e) {
        console.error('删除管理员失败', e);
        alert(this.t('remove_admin_failed') || '删除管理员失败，请检查权限');
      }
    },
  },
  mounted() { this.loadAdmins(); },
  template: `
  <div>
    <div class="flex-between mb-4">
      <h2 style="font-size:var(--fs-title)">
        <a href="#" @click.prevent="goBack" style="color:var(--color-muted);text-decoration:none;font-size:var(--fs-lg)">←</a>
        {{ t('admin_users') }}
      </h2>
    </div>

    <div v-if="loading" class="text-center mt-6">{{ t('loading') }}</div>

    <div v-else>
      <div v-if="!adminList.length" class="text-center mt-4">
        <div class="alert alert-info">{{ t('no_data') }}</div>
      </div>
      <div v-for="a in adminList" :key="a.id" class="card" style="padding:12px 16px">
        <div class="flex-between">
          <span style="font-size:var(--fs-lg)">{{ a.username }}</span>
          <button class="btn btn-sm btn-danger" @click="removeAdminUser(a.id)">{{ t('delete') }}</button>
        </div>
      </div>

      <div class="card mt-4">
        <div class="flex gap-2">
          <input class="input" v-model="newAdminName" :placeholder="t('admin_username')" style="flex:1" />
          <button class="btn btn-sm" @click="addAdminUser">{{ t('add_admin') }}</button>
        </div>
      </div>
    </div>
  </div>`
};
