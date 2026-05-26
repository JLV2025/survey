// Vue 3 应用入口 + 路由

const SurveyFill = window.__surveyFill;
const SurveyStats = window.__surveyStats;
const AdminDashboard = window.__adminDashboard;
const AdminSurveyList = window.__adminSurveyList;
const SurveyDesigner = window.__surveyDesigner;

const app = Vue.createApp({
  data() {
    return {
      currentUser: null,
      lang: currentLang,
      route: '',
      routeParams: {},
    };
  },

  computed: {
    currentView() {
      if (!this.currentUser) return null;
      if (this.route.startsWith('fill/')) return 'survey-fill';
      if (this.route.startsWith('stats/')) return 'survey-stats';
      if (this.route === 'admin' || this.route === 'admin/') return 'admin-dashboard';
      if (this.route.startsWith('admin/design/')) return 'survey-designer';
      if (this.route.startsWith('admin/surveys')) return 'admin-survey-list';
      if (this.route.startsWith('admin/submissions/')) return 'admin-submissions';
      if (this.route.startsWith('admin/results/')) return 'survey-stats';
      // 默认：如果是问卷ID就去填写页
      if (this.route) return 'survey-fill';
      return 'admin-dashboard';
    },
    routeKey() {
      return this.route + (this.lang || '');
    },
  },

  watch: {
    lang(val) {
      currentLang = val;
      document.documentElement.lang = val === 'zh' ? 'zh-CN' : 'en';
    },
  },

  methods: {
    t(key) { return t(key); },
    setLang(lang) { this.lang = lang; setLang(lang); },

    navigate(target) {
      if (target.startsWith('/')) target = target.slice(1);
      if (!target.startsWith('#')) target = '#' + target;
      const path = target.replace(/^#\/?/, '');
      this.route = path;
      this.routeParams = {};
      const parts = path.split('/');
      if (parts[0] === 'fill' && parts[1]) this.routeParams.id = parts[1];
      if (parts[0] === 'stats' && parts[1]) this.routeParams.id = parts[1];
      if (parts[0] === 'admin' && parts[1] === 'design' && parts[2]) this.routeParams.id = parts[2];
      if (parts[0] === 'admin' && parts[1] === 'submissions' && parts[2]) this.routeParams.id = parts[2];
      if (parts[0] === 'admin' && parts[1] === 'results' && parts[2]) this.routeParams.id = parts[2];
      if (parts.length === 1) this.routeParams.id = parts[0];
      window.location.hash = target.replace(/^#/, '#/');
    },

    goHome() {
      this.navigate('admin');
    },

    isAdminRoute() {
      const h = window.location.hash.replace(/^#\/?/, '');
      return !h || h.startsWith('admin');
    },

    parseHash() {
      const hash = window.location.hash.replace(/^#\/?/, '');
      if (hash) {
        this.route = hash;
        this.routeParams = {};
        const parts = hash.split('/');
        if (parts[0] === 'fill' && parts[1]) this.routeParams.id = parts[1];
        if (parts[0] === 'stats' && parts[1]) this.routeParams.id = parts[1];
        if (parts[0] === 'admin' && parts[1] === 'design' && parts[2]) this.routeParams.id = parts[2];
        if (parts[0] === 'admin' && parts[1] === 'submissions' && parts[2]) this.routeParams.id = parts[2];
        if (parts[0] === 'admin' && parts[1] === 'results' && parts[2]) this.routeParams.id = parts[2];
        if (parts[0] === 'admin' && parts[1] === 'surveys') { /* rien */ }
        if (parts.length === 1) this.routeParams.id = parts[0];
      } else {
        this.navigate('admin');
      }
    },
  },

  async mounted() {
    document.documentElement.lang = this.lang === 'zh' ? 'zh-CN' : 'en';
    if (this.isAdminRoute()) {
      try {
        const r = await fetchMe();
        if (r.ok) this.currentUser = r.data;
        else this.currentUser = { username: '', is_admin: false };
      } catch (e) {
        this.currentUser = { username: '', is_admin: false };
      }
    } else {
      this.currentUser = { username: '', is_admin: false };
    }
    this.parseHash();
    window.addEventListener('hashchange', () => {
      if (this.isAdminRoute() && (!this.currentUser || !this.currentUser.username)) {
        fetchMe().then(r => { if (r.ok) this.currentUser = r.data; }).catch(() => {});
      }
      this.parseHash();
    });
    window.__app = this;
  },
});

// 注册所有组件
app.component('survey-fill', SurveyFill);
app.component('survey-stats', SurveyStats);
app.component('admin-dashboard', AdminDashboard);
app.component('admin-survey-list', AdminSurveyList);
app.component('survey-designer', SurveyDesigner);

app.mount('#app');
