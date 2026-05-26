// 问卷填写 — 分步向导

window.__surveyFill = {
  props: ['routeParams'],
  data() {
    return {
      survey: null,
      questions: [],
      currentStep: 0,
      answers: {},
      submitted: false,
      submitting: false,
      error: '',
      loading: true,
    };
  },
  computed: {
    totalSteps() { return this.questions.length; },
    currentQuestion() { return this.questions[this.currentStep]; },
    isLastStep() { return this.currentStep >= this.totalSteps - 1; },
    isFirstStep() { return this.currentStep === 0; },
    canSubmit() {
      if (!this.questions.length) return false;
      for (const q of this.questions) {
        if (q.required && !this.answers[q.id]) return false;
      }
      return true;
    },
  },
  methods: {
    t(key) { return t(key); },
    getAnswer(questionId) { return this.answers[questionId] || ''; },
    setAnswer(questionId, value) {
      this.answers = { ...this.answers, [questionId]: value };
      this.saveDraft();
    },
    toggleCheckbox(questionId, optionId) {
      const current = (this.answers[questionId] || '').split(',').filter(Boolean);
      const idx = current.indexOf(optionId);
      if (idx >= 0) {
        current.splice(idx, 1);
      } else {
        current.push(optionId);
      }
      this.answers = { ...this.answers, [questionId]: current.join(',') };
      this.saveDraft();
    },
    saveDraft() {
      const surveyId = this.routeParams.id;
      if (surveyId) {
        localStorage.setItem('draft_' + surveyId, JSON.stringify(this.answers));
      }
    },
    loadDraft() {
      const surveyId = this.routeParams.id;
      if (surveyId) {
        const raw = localStorage.getItem('draft_' + surveyId);
        if (raw) {
          try { this.answers = JSON.parse(raw); } catch (e) { /* nothing */ }
        }
      }
    },
    clearDraft() {
      const surveyId = this.routeParams.id;
      if (surveyId) localStorage.removeItem('draft_' + surveyId);
    },
    nextStep() { if (!this.isLastStep) this.currentStep++; },
    prevStep() { if (!this.isFirstStep) this.currentStep--; },
    async handleSubmit() {
      if (!confirm(this.t('submit_confirm'))) return;
      if (this.submitting) return;
      this.submitting = true;
      const ans = [];
      for (const q of this.questions) {
        if (this.answers[q.id]) {
          ans.push({ question_id: q.id, content: this.answers[q.id] });
        }
      }
      try {
        const res = await submitSurvey(this.routeParams.id, ans);
        if (res.ok) {
          this.submitted = true;
          this.clearDraft();
          this.$emit('navigate', 'stats/' + this.routeParams.id);
        } else {
          this.error = res.message || this.t('server_error');
        }
      } catch (e) {
        this.error = this.t('server_error');
      }
      this.submitting = false;
    },
  },
  async mounted() {
    try {
      // 检查是否已提交
      const checkRes = await checkSubmitted(this.routeParams.id);
      if (checkRes.ok && checkRes.data && checkRes.data.submitted) {
        this.error = this.t('already_submitted');
        this.loading = false;
        return;
      }
      const res = await fetchSurvey(this.routeParams.id);
      if (res.ok && res.data) {
        this.survey = res.data.survey;
        this.questions = res.data.questions || [];
      } else {
        this.error = res.message || this.t('survey_not_found');
      }
    } catch (e) {
      this.error = this.t('survey_not_found');
    }
    this.loading = false;
    this.loadDraft();
  },
  template: `
  <div>
    <div v-if="loading" class="text-center mt-6">{{ t('loading') }}</div>

    <div v-else-if="error" class="text-center mt-6">
      <div class="alert alert-warn">{{ error }}</div>
    </div>

    <div v-else-if="!survey" class="text-center mt-6">
      <div class="alert alert-error">{{ t('survey_not_found') }}</div>
    </div>

    <div v-else>
      <h2 style="font-size:var(--fs-title);margin-bottom:8px">{{ survey.title }}</h2>
      <p style="color:var(--color-muted);margin-bottom:32px" v-if="survey.description">{{ survey.description }}</p>

      <!-- 步骤指示 -->
      <div class="step-indicator" v-if="questions.length > 1">
        <div v-for="(q, i) in questions" :key="i"
          class="step-dot"
          :class="{ active: i === currentStep, done: i < currentStep }">
        </div>
      </div>

      <!-- 当前题目 -->
      <div class="card" v-if="currentQuestion">
        <div class="question-block">
          <div class="question-title">
            {{ currentQuestion.title }}
            <span class="question-required" v-if="currentQuestion.required">*</span>
          </div>

          <!-- 单选题 -->
          <div v-if="currentQuestion.type === 'single'">
            <label v-for="opt in currentQuestion.options" :key="opt.id" class="option-item">
              <input type="radio"
                :name="'q_' + currentQuestion.id"
                :value="opt.id"
                :checked="getAnswer(currentQuestion.id) === opt.id"
                @change="setAnswer(currentQuestion.id, opt.id)" />
              {{ opt.content }}
            </label>
          </div>

          <!-- 多选题 -->
          <div v-if="currentQuestion.type === 'multiple'">
            <label v-for="opt in currentQuestion.options" :key="opt.id" class="option-item">
              <input type="checkbox"
                :checked="getAnswer(currentQuestion.id).split(',').indexOf(opt.id) >= 0"
                @change="toggleCheckbox(currentQuestion.id, opt.id)" />
              {{ opt.content }}
            </label>
          </div>

          <!-- 填空题（单行） -->
          <div v-if="currentQuestion.type === 'text'">
            <input class="input"
              :value="getAnswer(currentQuestion.id)"
              @input="setAnswer(currentQuestion.id, $event.target.value)"
              :maxlength="currentQuestion.char_limit || 524288"
              :placeholder="'请输入...'" />
            <div v-if="currentQuestion.char_limit" style="text-align:right;font-size:13px;color:var(--color-muted);margin-top:4px">
              {{ getAnswer(currentQuestion.id).length }} / {{ currentQuestion.char_limit }}
            </div>
          </div>

          <!-- 填空题（多行） -->
          <div v-if="currentQuestion.type === 'textarea'">
            <textarea class="textarea"
              :value="getAnswer(currentQuestion.id)"
              @input="setAnswer(currentQuestion.id, $event.target.value)"
              :maxlength="currentQuestion.char_limit || 524288"
              :placeholder="'请输入...'"
              rows="5"></textarea>
            <div v-if="currentQuestion.char_limit" style="text-align:right;font-size:13px;color:var(--color-muted);margin-top:4px">
              {{ getAnswer(currentQuestion.id).length }} / {{ currentQuestion.char_limit }}
            </div>
          </div>
        </div>
      </div>

      <!-- 导航 -->
      <div class="step-nav">
        <button class="btn btn-outline" @click="prevStep" :disabled="isFirstStep">
          {{ t('prev') }}
        </button>
        <button v-if="!isLastStep" class="btn" @click="nextStep">
          {{ t('next') }}
        </button>
        <button v-else class="btn" @click="handleSubmit" :disabled="!canSubmit || submitting">
          {{ submitting ? '...' : t('submit') }}
        </button>
      </div>
    </div>
  </div>`
};
