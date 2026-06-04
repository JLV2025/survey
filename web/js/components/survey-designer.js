// 拖拽问卷设计器

window.__surveyDesigner = {
  props: ['routeParams'],
  computed: {
    isPublished() { return this.survey && this.survey.status === 'published'; },
  },
  data() {
    return {
      survey: null,
      questions: [],
      loading: true,
      editingQid: null,
      editForm: {},
      editOptions: [],
      dragOver: false,
      dragIdx: null,
      showAddDialog: false,
      addType: 'single',
    };
  },
  methods: {
    t(key) { return t(key); },

    async loadSurvey() {
      const id = this.routeParams.id;
      if (!id) return;
      const res = await apiGet('/admin/surveys/' + id);
      if (res.ok && res.data) {
        this.survey = res.data;
        this.questions = res.data.questions || [];
      }
      this.loading = false;
    },

    goBack() { this.$emit('navigate', 'admin/surveys'); },

    // 拖入新题
    onDragStart(e, type) {
      e.dataTransfer.setData('text/plain', type);
      e.dataTransfer.effectAllowed = 'copy';
    },
    onDragOver(e) {
      e.preventDefault();
      this.dragOver = true;
      this.dragIdx = null;
    },
    onDragLeave() { this.dragOver = false; },
    async onDrop(e) {
        e.preventDefault();
        this.dragOver = false;
        if (this.isPublished) return;
        const type = e.dataTransfer.getData('text/plain');
        if (!type) return;
        await this.createQuestionOfType(type);
      },

      async createQuestionOfType(type) {
        if (this.isPublished) return;
        const typeNames = { single: '单选题', multiple: '多选题', text: '填空题', textarea: '多行文本' };
        const data = {
          type: type,
          title: this.t('type_' + type) || typeNames[type] || type,
          required: false,
          char_limit: 0,
          options: (type === 'single' || type === 'multiple') ? [
            { content: '选项 1' }, { content: '选项 2' },
          ] : [],
        };
        try {
          const res = await createQuestion(this.routeParams.id, data);
          if (res.ok) {
            await this.loadSurvey();
            this.showAddDialog = false;
            this.editQuestion(res.data);
          } else {
            alert(res.message || '添加题目失败');
          }
        } catch (e) {
          console.error('添加题目失败', e);
          alert('添加题目失败，请重试');
        }
      },

    // 画布内拖拽排序
    onCanvasDragStart(e, idx) {
      if (this.isPublished) return;
      e.dataTransfer.setData('text/plain', 'reorder');
      e.dataTransfer.setData('index', String(idx));
      e.dataTransfer.effectAllowed = 'move';
      const el = e.target.closest('.designer-question');
      if (el) el.classList.add('dragging');
    },
    onCanvasDragEnd(e) {
      const el = e.target.closest('.designer-question');
      if (el) el.classList.remove('dragging');
      // 清除所有 drag-over
      document.querySelectorAll('.designer-question').forEach(q => q.classList.remove('drag-over'));
    },
    onQuestionDragOver(e, idx) {
      e.preventDefault();
      e.dataTransfer.dropEffect = 'move';
      const el = e.target.closest('.designer-question');
      if (el) {
        document.querySelectorAll('.designer-question').forEach(q => q.classList.remove('drag-over'));
        el.classList.add('drag-over');
      }
      this.dragIdx = idx;
    },
    onQuestionDragLeave(e) {
      const el = e.target.closest('.designer-question');
      if (el) el.classList.remove('drag-over');
    },
    async onQuestionDrop(e, toIdx) {
      e.preventDefault();
      if (this.isPublished) return;
      const action = e.dataTransfer.getData('text/plain');
      if (action !== 'reorder') return;

      const fromIdx = parseInt(e.dataTransfer.getData('index'));
      if (isNaN(fromIdx) || fromIdx === toIdx) return;

      const original = [...this.questions];
      const reordered = [...this.questions];
      const [moved] = reordered.splice(fromIdx, 1);
      reordered.splice(toIdx, 0, moved);
      const ids = reordered.map(q => q.id);

      // 乐观更新
      this.questions = reordered;
      const r = await reorderQuestions(this.routeParams.id, ids);
      if (!r || !r.ok) this.questions = original;
    },

    // 题目编辑
    editQuestion(q) {
      if (this.isPublished) return;
      this.editingQid = q.id;
      this.editForm = {
        title: q.title,
        type: q.type,
        required: q.required,
        char_limit: q.char_limit || 0,
      };
      this.editOptions = (q.options || []).map(o => ({ id: o.id, content: o.content }));
    },
    cancelEdit() { this.editingQid = null; },

    addOption() {
      this.editOptions.push({ id: '', content: '' });
    },
    removeOption(idx) { this.editOptions.splice(idx, 1); },

    async saveQuestion() {
      if (this.isPublished || this._saving) return;
      if (!this.editForm.title.trim()) { alert(this.t('question_empty')); return; }
      this._saving = true;
      const data = {
        type: this.editForm.type,
        title: this.editForm.title,
        required: this.editForm.required,
        char_limit: this.editForm.char_limit || 0,
        options: this.editOptions.filter(o => o.content.trim()).map((o, i) => ({
          id: o.id || '',
          content: o.content,
          sort_order: i,
        })),
      };
      try {
        const r = await updateQuestion(this.routeParams.id, this.editingQid, data);
        if (!r.ok) { alert(r.message || '保存题目失败'); return; }
        this.editingQid = null;
        await this.loadSurvey();
      } catch (e) {
        console.error('保存题目失败', e);
        alert('保存题目失败，请重试');
      } finally {
        this._saving = false;
      }
    },

    async deleteQuestion(q) {
      if (this.isPublished) return;
      if (!confirm(this.t('confirm_delete'))) return;
      try {
        const r = await deleteQuestion(this.routeParams.id, q.id);
        if (!r.ok) { alert(r.message || '删除题目失败'); return; }
        if (this.editingQid === q.id) this.editingQid = null;
        await this.loadSurvey();
      } catch (e) {
        console.error('删除题目失败', e);
        alert('删除题目失败，请重试');
      }
    },

    // 预览
    previewMode: false,
    previewStep: 0,
    openPreview() {
      if (!this.questions.length) { alert(this.t('no_questions')); return; }
      this.previewMode = true;
      this.previewStep = 0;
    },
    closePreview() { this.previewMode = false; },
    nextPreview() {
      if (this.previewStep < this.questions.length - 1) this.previewStep++;
    },
    prevPreview() {
      if (this.previewStep > 0) this.previewStep--;
    },

    typeLabel(t) {
      const map = { single: 'type_single', multiple: 'type_multiple', text: 'type_text', textarea: 'type_textarea' };
      return this.t(map[t] || t);
    },
  },

  mounted() { this.loadSurvey(); },

  template: `
  <div>
    <div class="flex-between mb-4">
      <div>
        <a href="#" @click.prevent="goBack" style="color:var(--color-muted);text-decoration:none;font-size:var(--fs-lg)">←</a>
        <span style="font-size:var(--fs-xl);font-weight:700;margin-left:12px">
          {{ survey ? survey.title : t('designer_title') }}
        </span>
      </div>
      <div style="display:flex;gap:8px">
        <button class="btn btn-sm btn-outline" @click="showAddDialog=true" :disabled="isPublished">{{ t('add_question') }}</button>
        <button class="btn btn-sm btn-outline" @click="openPreview" :disabled="!questions.length">
          {{ t('preview') }}
        </button>
      </div>
    </div>

    <!-- 已发布锁定警告 -->
    <div v-if="isPublished" class="alert alert-warn mb-4" style="display:flex;align-items:center;justify-content:space-between">
      <span>⚠ 问卷已发布，题目不可编辑。如需修改题目请先关闭问卷。</span>
    </div>

    <!-- 添加题目对话框 -->
    <div v-if="showAddDialog" class="card mt-4">
      <h3 style="margin-bottom:16px">{{ t('add_question') }}</h3>
      <div style="display:flex;gap:8px;flex-wrap:wrap">
        <button class="btn btn-outline" @click="createQuestionOfType('single')">○ {{ t('type_single') }}</button>
        <button class="btn btn-outline" @click="createQuestionOfType('multiple')">☐ {{ t('type_multiple') }}</button>
        <button class="btn btn-outline" @click="createQuestionOfType('text')">— {{ t('type_text') }}</button>
        <button class="btn btn-outline" @click="createQuestionOfType('textarea')">☰ {{ t('type_textarea') }}</button>
      </div>
      <button class="btn btn-sm btn-outline mt-4" @click="showAddDialog=false">{{ t('cancel') }}</button>
    </div>

    <!-- 预览模式 -->
    <div v-if="previewMode" class="card">
      <div class="flex-between mb-4">
        <h3>{{ t('preview') }}</h3>
        <button class="btn btn-sm btn-outline" @click="closePreview">{{ t('cancel') }}</button>
      </div>
      <div class="step-indicator" v-if="questions.length > 1">
        <div v-for="(q, i) in questions" :key="i"
          class="step-dot"
          :class="{ active: i === previewStep, done: i < previewStep }">
        </div>
      </div>
      <div v-if="questions[previewStep]" class="question-block">
        <div class="question-title">
          {{ questions[previewStep].title }}
          <span class="question-required" v-if="questions[previewStep].required">*</span>
        </div>
        <div v-if="questions[previewStep].type === 'single'">
          <div v-for="opt in questions[previewStep].options" :key="opt.id" class="option-item">
            <input type="radio" disabled />
            {{ opt.content }}
          </div>
        </div>
        <div v-if="questions[previewStep].type === 'multiple'">
          <div v-for="opt in questions[previewStep].options" :key="opt.id" class="option-item">
            <input type="checkbox" disabled />
            {{ opt.content }}
          </div>
        </div>
        <div v-if="questions[previewStep].type === 'text'">
          <input class="input" disabled placeholder="请输入..." />
        </div>
        <div v-if="questions[previewStep].type === 'textarea'">
          <textarea class="textarea" disabled placeholder="请输入..." rows="4"></textarea>
        </div>
      </div>
      <div class="step-nav">
        <button class="btn btn-outline" @click="prevPreview" :disabled="previewStep === 0">{{ t('prev') }}</button>
        <span style="font-size:var(--fs-base);color:var(--color-muted)">{{ previewStep + 1 }} / {{ questions.length }}</span>
        <button class="btn" @click="nextPreview" :disabled="previewStep >= questions.length - 1">{{ t('next') }}</button>
      </div>
    </div>

    <!-- 设计模式 -->
    <div v-if="!previewMode" class="designer-layout">
      <!-- 左侧题型面板 -->
      <div v-if="!isPublished" class="type-panel">
        <div class="card" style="padding:12px">
          <div style="font-weight:600;margin-bottom:8px">{{ t('question_type') }}</div>
          <div class="type-item" draggable="true"
            @dragstart="onDragStart($event, 'single')">
            ○ {{ t('type_single') }}
          </div>
          <div class="type-item" draggable="true"
            @dragstart="onDragStart($event, 'multiple')">
            ☐ {{ t('type_multiple') }}
          </div>
          <div class="type-item" draggable="true"
            @dragstart="onDragStart($event, 'text')">
            — {{ t('type_text') }}
          </div>
          <div class="type-item" draggable="true"
            @dragstart="onDragStart($event, 'textarea')">
            ☰ {{ t('type_textarea') }}
          </div>
        </div>
      </div>

      <!-- 右侧画布 -->
      <div class="question-canvas"
        :class="{ 'canvas-placeholder': !questions.length && !dragOver }"
        @dragover="onDragOver"
        @dragleave="onDragLeave"
        @drop="onDrop">

        <div v-if="loading" class="text-center mt-6">{{ t('loading') }}</div>
        <div v-else-if="!questions.length && !dragOver" class="canvas-placeholder">
          {{ t('drop_here') }}
        </div>

        <div v-else>
          <div v-for="(q, idx) in questions" :key="q.id"
            class="designer-question"
            :class="{ 'drag-over': dragIdx === idx }"
            :draggable="!isPublished"
            @dragstart="onCanvasDragStart($event, idx)"
            @dragend="onCanvasDragEnd"
            @dragover="onQuestionDragOver($event, idx)"
            @dragleave="onQuestionDragLeave"
            @drop="onQuestionDrop($event, idx)">

            <div class="dq-header">
              <div>
                <span class="dq-type">{{ typeLabel(q.type) }}</span>
                <span v-if="q.required" style="color:var(--color-danger);font-size:13px;margin-left:4px">*</span>
              </div>
              <div v-if="!isPublished" class="dq-actions">
                <button @click="editQuestion(q)" :title="t('edit')">✎</button>
                <button @click="deleteQuestion(q)" :title="t('delete')">✕</button>
              </div>
            </div>

            <div style="font-size:var(--fs-lg);font-weight:500">
              {{ q.title }}
            </div>

            <!-- 选项预览 -->
            <div v-if="q.type === 'single' || q.type === 'multiple'" style="margin-top:8px">
              <div v-for="opt in q.options" :key="opt.id" style="font-size:14px;color:var(--color-muted);padding:2px 0">
                {{ q.type === 'single' ? '○' : '☐' }} {{ opt.content }}
              </div>
            </div>

            <!-- 编辑表单 -->
            <div v-if="editingQid === q.id" style="margin-top:12px;padding:16px;background:var(--color-bg);border-radius:var(--radius)">
              <div class="form-group">
                <label class="form-label">{{ t('question_title') }}</label>
                <input class="input" v-model="editForm.title" />
              </div>
              <div class="form-group">
                <label class="form-label">{{ t('question_type') }}</label>
                <select class="input" v-model="editForm.type" style="width:auto">
                  <option value="single">{{ t('type_single') }}</option>
                  <option value="multiple">{{ t('type_multiple') }}</option>
                  <option value="text">{{ t('type_text') }}</option>
                  <option value="textarea">{{ t('type_textarea') }}</option>
                </select>
              </div>
              <div class="form-group">
                <label style="display:flex;align-items:center;gap:8px;cursor:pointer">
                  <input type="checkbox" v-model="editForm.required" style="width:18px;height:18px" />
                  {{ t('required') }}
                </label>
              </div>

              <!-- 选择题的选项编辑 -->
              <div v-if="editForm.type === 'single' || editForm.type === 'multiple'" class="form-group">
                <label class="form-label">{{ t('options') }}</label>
                <div v-for="(opt, oi) in editOptions" :key="oi" class="flex gap-2" style="margin-bottom:6px">
                  <input class="input" v-model="opt.content" :placeholder="'选项 ' + (oi+1)" style="flex:1" />
                  <button class="btn btn-sm btn-danger" @click="removeOption(oi)">✕</button>
                </div>
                <button class="btn btn-sm btn-outline mt-2" @click="addOption">{{ t('add_option') }}</button>
              </div>

              <!-- 填空题字数限制 -->
              <div v-if="editForm.type === 'text' || editForm.type === 'textarea'" class="form-group">
                <label class="form-label">{{ t('char_limit') }}</label>
                <input class="input" type="number" v-model.number="editForm.char_limit" min="0" style="width:120px" />
                <div class="card-meta mt-2">0 = {{ t('no_limit') }}</div>
              </div>

              <div style="display:flex;gap:8px;margin-top:16px">
                <button class="btn btn-sm" @click="saveQuestion">{{ t('save') }}</button>
                <button class="btn btn-sm btn-outline" @click="cancelEdit">{{ t('cancel') }}</button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>`
};
