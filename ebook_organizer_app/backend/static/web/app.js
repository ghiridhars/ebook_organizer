/* ═══════════════════════════════════════════════════════════════════════
   eBook Organizer — Shared JavaScript
   API utilities, navigation, toast notifications, Alpine.js components
   ═══════════════════════════════════════════════════════════════════════ */

// ─── API Utility ──────────────────────────────────────────────────────
const API = {
  base: '/api',

  async get(path, params = {}) {
    const url = new URL(this.base + path, location.origin);
    Object.entries(params).forEach(([k, v]) => {
      if (v !== null && v !== undefined && v !== '') url.searchParams.set(k, v);
    });
    const res = await fetch(url);
    if (!res.ok) throw new Error(`API Error: ${res.status}`);
    return res.json();
  },

  async post(path, body = {}) {
    const res = await fetch(this.base + path, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    if (!res.ok) throw new Error(`API Error: ${res.status}`);
    return res.json();
  },

  async patch(path, body = {}) {
    const res = await fetch(this.base + path, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    if (!res.ok) throw new Error(`API Error: ${res.status}`);
    return res.json();
  },

  async del(path) {
    const res = await fetch(this.base + path, { method: 'DELETE' });
    if (!res.ok) throw new Error(`API Error: ${res.status}`);
    return res.json();
  },
};

// ─── Toast Notifications ──────────────────────────────────────────────
const Toast = {
  container: null,

  init() {
    if (this.container) return;
    this.container = document.createElement('div');
    this.container.className = 'toast-container';
    document.body.appendChild(this.container);
  },

  show(message, type = 'info', duration = 4000) {
    this.init();
    const toast = document.createElement('div');
    toast.className = `toast toast-${type}`;
    toast.textContent = message;
    this.container.appendChild(toast);

    setTimeout(() => {
      toast.style.animation = 'slideOut 0.3s ease forwards';
      setTimeout(() => toast.remove(), 300);
    }, duration);
  },

  success(msg) { this.show(msg, 'success'); },
  error(msg) { this.show(msg, 'error'); },
  info(msg) { this.show(msg, 'info'); },
};

// ─── Navigation Component ─────────────────────────────────────────────
function renderNav(activePage = '') {
  const nav = document.getElementById('main-nav');
  if (!nav) return;

  const pages = [
    { href: '/web/', icon: '📚', label: 'Library', id: 'library' },
    { href: '/web/classify.html', icon: '🏷️', label: 'Classify', id: 'classify' },
    { href: '/web/reorganize.html', icon: '📁', label: 'Reorganize', id: 'reorganize' },
    { href: '/web/stats.html', icon: '📊', label: 'Stats', id: 'stats' },
    { href: '/web/settings.html', icon: '⚙️', label: 'Settings', id: 'settings' },
  ];

  nav.innerHTML = `
    <div class="nav-inner">
      <a href="/web/" class="nav-brand">📖 <span>eBook Organizer</span></a>
      <button class="nav-toggle" onclick="document.querySelector('.nav-links').classList.toggle('open')">☰</button>
      <ul class="nav-links">
        ${pages.map(p => `
          <li><a href="${p.href}" class="nav-link ${activePage === p.id ? 'active' : ''}">${p.icon} ${p.label}</a></li>
        `).join('')}
      </ul>
    </div>
  `;
}

// ─── Utility Helpers ──────────────────────────────────────────────────
function formatBytes(bytes) {
  if (!bytes || bytes === 0) return '0 B';
  const sizes = ['B', 'KB', 'MB', 'GB'];
  const i = Math.floor(Math.log(bytes) / Math.log(1024));
  return `${(bytes / Math.pow(1024, i)).toFixed(1)} ${sizes[i]}`;
}

function formatDate(dateStr) {
  if (!dateStr) return '—';
  const d = new Date(dateStr);
  return d.toLocaleDateString('en-US', { year: 'numeric', month: 'short', day: 'numeric' });
}

function debounce(fn, delay = 300) {
  let timer;
  return (...args) => {
    clearTimeout(timer);
    timer = setTimeout(() => fn(...args), delay);
  };
}

function getFormatBadgeClass(format) {
  const map = { epub: 'badge-epub', pdf: 'badge-pdf', mobi: 'badge-mobi', azw: 'badge-mobi', azw3: 'badge-mobi' };
  return map[format] || 'badge-epub';
}

function getCoverUrl(book) {
  return book.cover_url || `/api/ebooks/${book.id}/cover`;
}

// ─── Alpine.js Data Components ────────────────────────────────────────

// Library page
function libraryData() {
  return {
    books: [],
    total: 0,
    loading: true,
    search: '',
    category: '',
    format: '',
    author: '',
    sort: 'created_at',
    order: 'desc',
    page: 1,
    pageSize: 30,
    categories: [],
    authors: [],
    taxonomy: null,
    viewMode: 'grid',
    uploading: false,

    async init() {
      this.viewMode = localStorage.getItem('libraryViewMode') || 'grid';
      await Promise.all([this.loadTaxonomy(), this.loadAuthors()]);
      await this.loadBooks();
    },

    toggleViewMode() {
      this.viewMode = this.viewMode === 'grid' ? 'list' : 'grid';
      localStorage.setItem('libraryViewMode', this.viewMode);
    },

    async loadTaxonomy() {
      try {
        this.taxonomy = await API.get('/organization/taxonomy');
        this.categories = Object.keys(this.taxonomy || {});
      } catch (e) {
        console.warn('Failed to load taxonomy:', e);
      }
    },

    async loadAuthors() {
      try {
        this.authors = await API.get('/ebooks/authors');
      } catch (e) {
        console.warn('Failed to load authors:', e);
      }
    },

    async loadBooks() {
      this.loading = true;
      try {
        const params = {
          skip: (this.page - 1) * this.pageSize,
          limit: this.pageSize,
          sort: this.sort || 'created_at',
          order: this.order || 'desc',
        };
        if (this.search) params.search = this.search;
        if (this.category) params.category = this.category;
        if (this.format) params.format = this.format;
        if (this.author) params.author = this.author;

        this.books = await API.get('/ebooks/', params);
        // Estimate total (API returns array, not paginated response with total)
        this.total = this.books.length === this.pageSize ? (this.page * this.pageSize + 1) : ((this.page - 1) * this.pageSize + this.books.length);
      } catch (e) {
        Toast.error('Failed to load books');
        console.error(e);
      }
      this.loading = false;
    },

    async doSearch() {
      this.page = 1;
      if (this.search && this.search.length >= 2) {
        try {
          const res = await API.get('/ebooks/search', { q: this.search, page_size: this.pageSize });
          this.books = res.results.map(r => ({
            id: r.id, title: r.title, author: r.author,
            category: r.category, sub_genre: r.sub_genre,
            file_format: r.format, score: r.score,
            cover_url: `/api/ebooks/${r.id}/cover`,
          }));
          this.total = res.total;
        } catch (e) {
          await this.loadBooks();
        }
      } else {
        await this.loadBooks();
      }
    },

    async onFilterChange() {
      this.page = 1;
      await this.loadBooks();
    },

    get totalPages() {
      return Math.max(1, Math.ceil(this.total / this.pageSize));
    },

    async goPage(p) {
      this.page = p;
      await this.loadBooks();
      window.scrollTo({ top: 0, behavior: 'smooth' });
    },

    async uploadBook(e) {
      const file = e.target.files[0];
      if (!file) return;
      
      this.uploading = true;
      const formData = new FormData();
      formData.append('file', file);
      
      try {
        const res = await fetch(API.base + '/ebooks/upload', {
          method: 'POST',
          body: formData
        });
        
        if (!res.ok) throw new Error();
        Toast.success('File uploaded to Inbox! Background watcher will process it shortly.');
        
        // Polling occasionally to refresh library
        setTimeout(() => this.loadBooks(), 3000);
      } catch (err) {
        Toast.error('Upload failed');
      }
      
      this.uploading = false;
      e.target.value = ''; // Reset input
    },

    openBook(id) {
      window.location.href = `/web/book.html?id=${id}`;
    },
  };
}

// Book detail page
function bookDetailData() {
  return {
    book: null,
    loading: true,
    editing: false,
    form: {},
    saving: false,
    taxonomy: null,
    subGenres: [],
    newTag: '',

    async init() {
      const id = new URLSearchParams(location.search).get('id');
      if (!id) { window.location.href = '/web/'; return; }

      try {
        this.book = await API.get(`/ebooks/${id}`);
        this.form = { ...this.book };
        this.taxonomy = await API.get('/organization/taxonomy');
        this.updateSubGenres();
      } catch (e) {
        Toast.error('Failed to load book');
      }
      this.loading = false;
    },

    startEditing() {
      this.editing = true;
      this.form = { ...this.book };
    },

    cancelEditing() {
      this.editing = false;
      this.form = { ...this.book };
    },

    updateSubGenres() {
      if (this.form.category && this.taxonomy && this.taxonomy[this.form.category]) {
        this.subGenres = this.taxonomy[this.form.category];
      } else {
        this.subGenres = [];
      }
    },

    async save() {
      this.saving = true;
      try {
        await API.patch(`/ebooks/${this.book.id}`, {
          title: this.form.title,
          author: this.form.author,
          category: this.form.category,
          sub_genre: this.form.sub_genre,
          description: this.form.description,
          tags: this.form.tags || [],
        });
        this.book = await API.get(`/ebooks/${this.book.id}`);
        this.form = { ...this.book };
        this.editing = false;
        Toast.success('Metadata saved');
      } catch (e) {
        Toast.error('Failed to save');
      }
      this.saving = false;
    },

    addTag() {
      if (!this.newTag.trim()) return;
      if (!this.form.tags) this.form.tags = [];
      if (!this.form.tags.includes(this.newTag.trim())) {
        this.form.tags.push(this.newTag.trim());
      }
      this.newTag = '';
    },

    removeTag(tag) {
      this.form.tags = (this.form.tags || []).filter(t => t !== tag);
    },

    async reClassify() {
      try {
        await API.post('/organization/classify/' + this.book.id);
        this.book = await API.get(`/ebooks/${this.book.id}`);
        this.form = { ...this.book };
        Toast.success('Re-classified');
      } catch (e) {
        Toast.error('Classification failed');
      }
    },

    async deleteEbook() {
      if (!confirm('Are you sure you want to delete this book from the index? The file will NOT be deleted from disk.')) return;
      try {
        await API.del(`/ebooks/${this.book.id}`);
        Toast.success('Book removed from index');
        setTimeout(() => window.location.href = '/web/', 1500);
      } catch (e) {
        Toast.error('Failed to delete book');
      }
    },

    canRead() {
      return this.book && this.book.file_format === 'epub';
    },
  };
}

// Classifier page
function classifierData() {
  return {
    books: [],
    taxonomy: {},
    loading: false,
    classifyingAll: false,
    categories: [],
    stats: null,
    searchQuery: '',
    sortColumn: 'title',
    sortAscending: true,
    overrides: {}, // map of book.id -> {category, sub_genre}
    savingOverrides: false,

    async init() {
      try {
        this.taxonomy = await API.get('/organization/taxonomy');
        this.categories = Object.keys(this.taxonomy || {});
      } catch (e) { /* ignore */ }
      await Promise.all([this.loadStats(), this.loadUnclassified()]);
    },

    async loadStats() {
      try {
        this.stats = await API.get('/organization/stats');
      } catch (e) {
        console.warn('Failed to load org stats');
      }
    },

    async loadUnclassified() {
      this.loading = true;
      try {
        // Fetch up to 500 unclassified books for the UI
        this.books = await API.get('/organization/unclassified', { limit: 500 });
        // Initialize overrides state for any new books
        this.books.forEach(b => {
          if (!this.overrides[b.id]) {
            this.overrides[b.id] = {
              category: b.category || '',
              sub_genre: b.sub_genre || '',
               _originalCategory: b.category || '',
               _originalSubGenre: b.sub_genre || ''
            };
          }
        });
      } catch (e) {
        Toast.error('Failed to load books');
      }
      this.loading = false;
    },

    get filteredBooks() {
      let filtered = this.books;
      if (this.searchQuery) {
        const q = this.searchQuery.toLowerCase();
        filtered = filtered.filter(b => 
          (b.title && b.title.toLowerCase().includes(q)) || 
          (b.author && b.author.toLowerCase().includes(q))
        );
      }
      
      return filtered.sort((a, b) => {
        let cmp = 0;
        if (this.sortColumn === 'title') {
          cmp = (a.title || '').localeCompare(b.title || '');
        } else if (this.sortColumn === 'author') {
          cmp = (a.author || '').localeCompare(b.author || '');
        } else if (this.sortColumn === 'category') {
          const catA = this.overrides[a.id]?.category || a.category || '';
          const catB = this.overrides[b.id]?.category || b.category || '';
          cmp = catA.localeCompare(catB);
        }
        return this.sortAscending ? cmp : -cmp;
      });
    },

    toggleSort(col) {
      if (this.sortColumn === col) {
        this.sortAscending = !this.sortAscending;
      } else {
        this.sortColumn = col;
        this.sortAscending = true;
      }
    },

    setOverride(bookId, field, value) {
      if (!this.overrides[bookId]) {
        this.overrides[bookId] = { category: '', sub_genre: '', _originalCategory: '', _originalSubGenre: '' };
      }
      this.overrides[bookId][field] = value;
      // If category changes, reset sub-genre unless it's valid for the new category
      if (field === 'category') {
        const validSubs = this.getSubGenres(value);
        if (!validSubs.includes(this.overrides[bookId].sub_genre)) {
          this.overrides[bookId].sub_genre = '';
        }
      }
    },

    hasOverride(bookId) {
      const o = this.overrides[bookId];
      if (!o) return false;
      return o.category !== o._originalCategory || o.sub_genre !== o._originalSubGenre;
    },

    undoOverride(bookId) {
      if (this.overrides[bookId]) {
        this.overrides[bookId].category = this.overrides[bookId]._originalCategory;
        this.overrides[bookId].sub_genre = this.overrides[bookId]._originalSubGenre;
      }
    },

    get hasAnyOverrides() {
      return this.books.some(b => this.hasOverride(b.id));
    },

    async saveOverrides() {
      this.savingOverrides = true;
      let successCount = 0;
      let failCount = 0;

      for (const book of this.books) {
        if (this.hasOverride(book.id)) {
          try {
            const ov = this.overrides[book.id];
            await API.patch(`/ebooks/${book.id}`, { category: ov.category, sub_genre: ov.sub_genre });
            ov._originalCategory = ov.category;
            ov._originalSubGenre = ov.sub_genre;
            successCount++;
          } catch (e) {
            failCount++;
          }
        }
      }

      if (successCount > 0) Toast.success(`Saved ${successCount} overrides`);
      if (failCount > 0) Toast.error(`Failed to save ${failCount} overrides`);

      await Promise.all([this.loadStats(), this.loadUnclassified()]);
      this.savingOverrides = false;
    },

    async classifySingle(book) {
      try {
        const res = await API.post(`/organization/classify/${book.id}`);
        Toast.success(`Classified: ${book.title}`);
        
        // Update local object immediately to avoid full reload
        if (this.overrides[book.id]) {
          this.overrides[book.id].category = res.category || '';
          this.overrides[book.id].sub_genre = res.sub_genre || '';
          this.overrides[book.id]._originalCategory = res.category || '';
          this.overrides[book.id]._originalSubGenre = res.sub_genre || '';
        }
        await this.loadStats();
      } catch (e) {
        Toast.error(`Classification failed for: ${book.title}`);
      }
    },

    async classifyAll() {
      this.classifyingAll = true;
      try {
        await API.post('/organization/batch-classify');
        Toast.info('Batch classification started');
        // Poll for completion
        await new Promise(r => setTimeout(r, 3000));
        await Promise.all([this.loadStats(), this.loadUnclassified()]);
        Toast.success('Batch classification complete');
      } catch (e) {
        Toast.error('Batch classification failed');
      }
      this.classifyingAll = false;
    },

    getSubGenres(category) {
      return this.taxonomy[category] || [];
    },
  };
}

// Reorganize page
function reorganizeData() {
  return {
    preview: null,
    loading: false,
    applying: false,
    
    // Config panel state
    config: {
      destination: '/tmp/library_organized', // Default mock path, user will change it
      operation: 'move',
      includeUnclassified: false,
    },
    
    // Sorting state for preview table
    sortColumn: 'title',
    sortAscending: true,

    async loadPreview() {
      if (!this.config.destination) {
        Toast.error("Please enter a destination path");
        return;
      }
      this.loading = true;
      try {
        this.preview = await API.post('/organization/reorganize-preview', {
          destination: this.config.destination,
          operation: this.config.operation,
          include_unclassified: this.config.includeUnclassified
        });
        Toast.info(`${this.preview.planned_moves.length} files to reorganize`);
      } catch (e) {
        Toast.error('Failed to load preview');
        console.error(e);
      }
      this.loading = false;
    },

    async applyReorganization() {
      if (!this.preview || !this.preview.planned_moves.length) return;
      if (!confirm('This will modify files on disk. Continue?')) return;
      
      this.applying = true;
      try {
        const result = await API.post('/organization/reorganize', {
          destination: this.config.destination,
          operation: this.config.operation,
          include_unclassified: this.config.includeUnclassified
        });
        
        if (result.failed > 0) {
          Toast.warning(`Reorganization complete. ${result.succeeded} succeeded, ${result.failed} failed.`);
        } else {
          Toast.success(`Successfully reorganized ${result.succeeded} files!`);
        }
        this.preview = null;
      } catch (e) {
        Toast.error('Reorganization failed');
      }
      this.applying = false;
    },
    
    get sortedMoves() {
      if (!this.preview || !this.preview.planned_moves) return [];
      
      return [...this.preview.planned_moves].sort((a, b) => {
        let cmp = 0;
        if (this.sortColumn === 'title') {
          cmp = (a.title || '').localeCompare(b.title || '');
        } else if (this.sortColumn === 'author') {
          cmp = (a.author || '').localeCompare(b.author || '');
        } else if (this.sortColumn === 'category') {
          const catA = (a.category || '') + (a.sub_genre || '');
          const catB = (b.category || '') + (b.sub_genre || '');
          cmp = catA.localeCompare(catB);
        } else if (this.sortColumn === 'target') {
          cmp = (a.target_path || '').localeCompare(b.target_path || '');
        }
        return this.sortAscending ? cmp : -cmp;
      });
    },

    toggleSort(col) {
      if (this.sortColumn === col) {
        this.sortAscending = !this.sortAscending;
      } else {
        this.sortColumn = col;
        this.sortAscending = true;
      }
    }
  };
}

// Stats page
function statsData() {
  return {
    stats: null,
    watcherStatus: null,
    loading: true,
    recentBooks: [],

    async init() {
      await Promise.all([
        this.loadStats(),
        this.loadWatcherStatus(),
        this.loadRecent(),
      ]);
      this.loading = false;
    },

    async loadStats() {
      try {
        this.stats = await API.get('/ebooks/stats/library');
      } catch (e) {
        console.error('Failed to load stats:', e);
      }
    },

    async loadWatcherStatus() {
      try {
        this.watcherStatus = await API.get('/watcher/status');
      } catch (e) {
        console.warn('Watcher status unavailable');
      }
    },

    async loadRecent() {
      try {
        this.recentBooks = await API.get('/ebooks/', { limit: 10, sort: 'created_at', order: 'desc' });
      } catch (e) { /* ignore */ }
    },

    async optimizeIndex() {
      Toast.info('Optimizing search index...');
      try {
        // Trigger a rebuild via the search endpoint pattern
        await API.post('/sync/trigger', { provider: 'local', local_path: '', full_sync: false });
        Toast.success('Index optimization triggered');
      } catch (e) {
        Toast.error('Optimization failed');
      }
    },

    async toggleWatcher() {
      try {
        if (this.watcherStatus?.running) {
          await API.post('/watcher/stop');
          Toast.success('Watcher stopped');
        } else {
          await API.post('/watcher/start');
          Toast.success('Watcher started');
        }
        await this.loadWatcherStatus();
      } catch (e) {
        Toast.error('Failed to change watcher status');
      }
    },
  };
}

// Settings page
function settingsData() {
  return {
    theme: 'system',
    watcher: null,
    loading: true,

    async init() {
      this.theme = localStorage.getItem('appTheme') || 'system';
      this.applyTheme();
      await this.loadWatcherStatus();
    },

    saveSettings() {
      localStorage.setItem('appTheme', this.theme);
      this.applyTheme();
    },

    applyTheme() {
      if (this.theme === 'dark') {
        document.body.classList.add('theme-dark');
        document.body.classList.remove('theme-light');
      } else if (this.theme === 'light') {
        document.body.classList.add('theme-light');
        document.body.classList.remove('theme-dark');
      } else {
        document.body.classList.remove('theme-dark', 'theme-light');
      }
    },

    async loadWatcherStatus() {
      this.loading = true;
      try {
        this.watcher = await API.get('/watcher/status');
      } catch (e) {
        console.warn('Watcher status unavailable');
      }
      this.loading = false;
    },

    async toggleWatcher() {
      try {
        if (this.watcher?.running) {
          await API.post('/watcher/stop');
          Toast.success('Watcher stopped');
        } else {
          await API.post('/watcher/start');
          Toast.success('Watcher started');
        }
        await this.loadWatcherStatus();
      } catch (e) {
        Toast.error('Failed to change watcher status');
      }
    },

    async optimizeIndex() {
      Toast.info('Optimizing search index...');
      try {
        // Trigger a rebuild via the sync endpoint
        await API.post('/sync/trigger', { provider: 'local', local_path: '', full_sync: false });
        Toast.success('Index optimization triggered');
      } catch (e) {
        Toast.error('Optimization failed');
      }
    }
  };
}

// Initialize theme globally
(function() {
  const t = localStorage.getItem('appTheme') || 'system';
  if (t === 'dark') document.body.classList.add('theme-dark');
  else if (t === 'light') document.body.classList.add('theme-light');
})();
