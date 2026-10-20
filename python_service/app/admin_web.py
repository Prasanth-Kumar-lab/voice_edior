"""Standalone Web Admin Dashboard served at http://127.0.0.1:8088/admin.

Connects directly to the `vocalpolish_studio` MongoDB database via the FastAPI `/api/*` endpoints.
"""

ADMIN_HTML = r"""<!DOCTYPE html>
<html lang="en" class="dark">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>VocalPolish Studio · Web Admin Command Center</title>
  <script src="https://cdn.tailwindcss.com"></script>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800;900&display=swap" rel="stylesheet">
  <style>
    body {
      font-family: 'Inter', sans-serif;
      background-color: #0B0D12;
      color: #F4F6FB;
    }
    .vp-gradient {
      background: linear-gradient(135deg, #7C6CFF 0%, #22D3EE 100%);
    }
    .vp-text-gradient {
      background: linear-gradient(135deg, #7C6CFF 0%, #22D3EE 100%);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
    }
    .vp-card {
      background-color: #141824;
      border: 1px solid #2A3148;
      border-radius: 16px;
    }
    .vp-surface-alt {
      background-color: #1C2233;
      border: 1px solid #2A3148;
    }
    .vp-glow {
      box-shadow: 0 10px 30px -5px rgba(124, 108, 255, 0.35);
    }
    ::-webkit-scrollbar { width: 6px; height: 6px; }
    ::-webkit-scrollbar-track { background: #0B0D12; }
    ::-webkit-scrollbar-thumb { background: #2A3148; border-radius: 999px; }
  </style>
</head>
<body class="min-h-screen flex flex-col">

  <!-- Top Navbar -->
  <header class="sticky top-0 z-30 bg-[#0B0D12]/90 backdrop-blur-md border-b border-[#2A3148] px-6 py-4">
    <div class="max-w-7xl mx-auto flex flex-wrap items-center justify-between gap-4">
      <div class="flex items-center gap-3">
        <div class="w-10 h-10 rounded-xl vp-gradient vp-glow flex items-center justify-center font-black text-white text-lg">
          VP
        </div>
        <div>
          <h1 class="text-lg font-extrabold tracking-tight flex items-center gap-2">
            <span class="vp-text-gradient">VocalPolish Studio</span>
            <span class="text-xs px-2.5 py-0.5 rounded-full bg-[#1C2233] border border-[#2A3148] text-[#22D3EE] font-bold">WEB ADMIN</span>
          </h1>
          <p class="text-xs text-[#9AA3B8]">MongoDB Compass DB: <code id="dbNameBadge" class="text-[#22D3EE] font-mono">vocalpolish_studio</code> · Real-Time Sync with Android App</p>
        </div>
      </div>

      <!-- Navigation Tabs -->
      <nav class="flex items-center gap-2 overflow-x-auto">
        <button onclick="switchTab('overview')" id="tabBtn-overview" class="tab-btn px-4 py-2 rounded-full text-sm font-bold vp-gradient text-white">Overview & Revenue</button>
        <button onclick="switchTab('users')" id="tabBtn-users" class="tab-btn px-4 py-2 rounded-full text-sm font-semibold text-[#9AA3B8] hover:text-white bg-[#141824] border border-[#2A3148]">Users & Profiles</button>
        <button onclick="switchTab('plans')" id="tabBtn-plans" class="tab-btn px-4 py-2 rounded-full text-sm font-semibold text-[#9AA3B8] hover:text-white bg-[#141824] border border-[#2A3148]">Subscriptions</button>
        <button onclick="switchTab('features')" id="tabBtn-features" class="tab-btn px-4 py-2 rounded-full text-sm font-semibold text-[#9AA3B8] hover:text-white bg-[#141824] border border-[#2A3148]">App Features & DSP</button>
        <button onclick="switchTab('usage')" id="tabBtn-usage" class="tab-btn px-4 py-2 rounded-full text-sm font-semibold text-[#9AA3B8] hover:text-white bg-[#141824] border border-[#2A3148]">Usage Telemetry</button>
      </nav>

      <div class="flex items-center gap-3">
        <span id="syncIndicator" class="flex items-center gap-2 text-xs px-3 py-1.5 rounded-full bg-[#141824] border border-[#2A3148]">
          <span class="w-2 h-2 rounded-full bg-emerald-400 animate-pulse"></span>
          <span>MongoDB Connected</span>
        </span>
        <button onclick="fetchState()" class="px-3.5 py-1.5 rounded-xl bg-[#1C2233] hover:bg-[#2A3148] text-xs font-bold transition">↻ Refresh</button>
      </div>
    </div>
  </header>

  <!-- Main Content Container -->
  <main class="flex-1 max-w-7xl w-full mx-auto px-6 py-8">

    <!-- 1. OVERVIEW & REVENUE TAB -->
    <section id="tab-overview" class="space-y-6">
      <!-- Hero Revenue Card -->
      <div class="rounded-2xl p-7 vp-gradient vp-glow flex flex-col md:flex-row md:items-center justify-between gap-6">
        <div>
          <div class="flex items-center gap-2 text-xs font-extrabold uppercase tracking-wider text-white/90">
            <span>TOTAL ANNUALIZED APP REVENUE (MONGODB LIVE)</span>
            <span class="px-2.5 py-0.5 rounded-full bg-black/30 text-white">+28.4% MoM</span>
          </div>
          <div id="kpiTotalRevenue" class="text-4xl md:text-5xl font-black text-white mt-2">$0.00</div>
          <p id="kpiMrrSub" class="text-sm text-white/90 mt-2">Monthly Recurring Revenue (MRR): $0.00 / mo · 0 Active Subscribers</p>
        </div>
        <div class="flex flex-wrap gap-3">
          <button onclick="openModal('modalAddPlan')" class="px-4 py-2.5 rounded-xl bg-black/30 hover:bg-black/40 text-white text-xs font-bold border border-white/20 transition">+ Add Subscription Tier</button>
          <button onclick="openModal('modalAddFeature')" class="px-4 py-2.5 rounded-xl bg-white text-[#0B0D12] hover:bg-white/90 text-xs font-extrabold transition">+ Deploy New App Feature</button>
        </div>
      </div>

      <!-- 4 KPI Cards -->
      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <div onclick="switchTab('users')" class="vp-card p-5 cursor-pointer hover:border-[#22D3EE] transition">
          <div class="flex justify-between items-center text-xs text-[#9AA3B8]">
            <span>REGISTERED USERS</span>
            <span class="text-[#22D3EE]">View →</span>
          </div>
          <div id="kpiUsersCount" class="text-3xl font-extrabold mt-2">0</div>
          <div id="kpiUsersSub" class="text-xs text-[#22D3EE] mt-1">0 active · 0 deactivated</div>
        </div>

        <div onclick="switchTab('plans')" class="vp-card p-5 cursor-pointer hover:border-[#7C6CFF] transition">
          <div class="flex justify-between items-center text-xs text-[#9AA3B8]">
            <span>SUBSCRIPTION TIERS</span>
            <span class="text-[#7C6CFF]">Manage →</span>
          </div>
          <div id="kpiPlansCount" class="text-3xl font-extrabold mt-2">0</div>
          <div id="kpiPlansSub" class="text-xs text-[#7C6CFF] mt-1">Synced to mobile store</div>
        </div>

        <div onclick="switchTab('features')" class="vp-card p-5 cursor-pointer hover:border-emerald-400 transition">
          <div class="flex justify-between items-center text-xs text-[#9AA3B8]">
            <span>ACTIVE APP FEATURES</span>
            <span class="text-emerald-400">Configure →</span>
          </div>
          <div id="kpiFeaturesCount" class="text-3xl font-extrabold mt-2">0</div>
          <div class="text-xs text-emerald-400 mt-1">Podcast Bass/Treble & DSP</div>
        </div>

        <div onclick="switchTab('usage')" class="vp-card p-5 cursor-pointer hover:border-amber-400 transition">
          <div class="flex justify-between items-center text-xs text-[#9AA3B8]">
            <span>AUDIO MASTERS PROCESSED</span>
            <span class="text-amber-400">Telemetry →</span>
          </div>
          <div id="kpiMastersCount" class="text-3xl font-extrabold mt-2">0</div>
          <div id="kpiMinutesSub" class="text-xs text-amber-400 mt-1">0 total studio minutes</div>
        </div>
      </div>

      <!-- Revenue Chart + Recent Transactions -->
      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div class="vp-card p-6 lg:col-span-1 flex flex-col justify-between">
          <div>
            <h3 class="text-base font-bold flex items-center justify-between">
              <span>Monthly Revenue Trajectory</span>
              <span class="text-xs text-[#9AA3B8]">USD ($k)</span>
            </h3>
            <p class="text-xs text-[#9AA3B8] mt-1">Stored in <code class="text-[#22D3EE]">vocalpolish_studio.settings</code></p>
          </div>
          <div id="revenueBarsContainer" class="h-48 flex items-end justify-between gap-3 pt-8"></div>
        </div>

        <div class="vp-card p-6 lg:col-span-2">
          <div class="flex items-center justify-between mb-4">
            <div>
              <h3 class="text-base font-bold">Recent Subscription Transactions</h3>
              <p class="text-xs text-[#9AA3B8]">Live collection: <code class="text-[#22D3EE]">vocalpolish_studio.transactions</code></p>
            </div>
            <button onclick="openModal('modalRecordPayment')" class="px-3 py-1.5 rounded-xl bg-emerald-500/20 border border-emerald-500/40 text-emerald-300 text-xs font-bold hover:bg-emerald-500/30">+ Record Payment</button>
          </div>
          <div id="transactionsList" class="space-y-3 max-h-72 overflow-y-auto pr-1"></div>
        </div>
      </div>
    </section>

    <!-- 2. USERS DIRECTORY & PROFILE MANAGEMENT TAB -->
    <section id="tab-users" class="hidden space-y-6">
      <div class="flex flex-wrap items-center justify-between gap-4">
        <div>
          <h2 class="text-2xl font-extrabold">Creator Directory & User Profiles</h2>
          <p class="text-sm text-[#9AA3B8]">Inspect user profiles, track audio usage, change subscriptions, deactivate accounts, or remove users permanently.</p>
        </div>
        <button onclick="openModal('modalAddUser')" class="px-4 py-2.5 rounded-xl vp-gradient text-white text-sm font-bold vp-glow">+ Provision Studio User</button>
      </div>

      <div class="flex flex-wrap items-center gap-3">
        <input id="userSearchInput" oninput="renderUsers()" type="text" placeholder="Search by name, email, role, device or plan..." class="flex-1 min-w-[260px] px-4 py-2.5 rounded-xl vp-surface-alt text-sm focus:outline-none focus:border-[#22D3EE]" />
        <select id="userStatusFilter" onchange="renderUsers()" class="px-4 py-2.5 rounded-xl vp-surface-alt text-sm focus:outline-none">
          <option value="all">All Statuses</option>
          <option value="active">Active Only</option>
          <option value="deactivated">Deactivated Only</option>
          <option value="pro">Pro Subscribers</option>
        </select>
      </div>

      <div id="usersGrid" class="grid grid-cols-1 md:grid-cols-2 gap-4"></div>
    </section>

    <!-- 3. SUBSCRIPTIONS MANAGEMENT TAB -->
    <section id="tab-plans" class="hidden space-y-6">
      <div class="flex flex-wrap items-center justify-between gap-4">
        <div>
          <h2 class="text-2xl font-extrabold">Subscription Plans & Pricing</h2>
          <p class="text-sm text-[#9AA3B8]">Add, toggle, or remove subscription tiers in <code class="text-[#22D3EE]">vocalpolish_studio.plans</code>. Changes appear immediately in the mobile app's Pro Pass screen.</p>
        </div>
        <button onclick="openModal('modalAddPlan')" class="px-4 py-2.5 rounded-xl vp-gradient text-white text-sm font-bold vp-glow">+ Add New Subscription Plan</button>
      </div>

      <div id="plansGrid" class="grid grid-cols-1 md:grid-cols-3 gap-5"></div>
    </section>

    <!-- 4. APP FEATURES & DSP FUNCTIONALITIES TAB -->
    <section id="tab-features" class="hidden space-y-6">
      <div class="flex flex-wrap items-center justify-between gap-4">
        <div>
          <h2 class="text-2xl font-extrabold">Dynamic App Functionalities & Podcast Filters</h2>
          <p class="text-sm text-[#9AA3B8]">Add new Podcast Bass/Treble filters or DSP features here — they are automatically registered in the Python DSP engine and appear as selectable chips in the mobile app!</p>
        </div>
        <button onclick="openModal('modalAddFeature')" class="px-4 py-2.5 rounded-xl vp-gradient text-white text-sm font-bold vp-glow">+ Add New Filter / Functionality</button>
      </div>

      <!-- Global App Banner & Switches -->
      <div class="vp-card p-6 space-y-4">
        <div class="flex flex-wrap items-center justify-between gap-4">
          <div class="flex-1 min-w-[280px]">
            <label class="text-xs font-bold uppercase text-[#22D3EE]">Live In-App Announcement Banner</label>
            <div class="flex gap-2 mt-1.5">
              <input id="bannerInput" type="text" class="flex-1 px-3.5 py-2 rounded-xl vp-surface-alt text-sm" />
              <button onclick="saveGlobalSettings()" class="px-4 py-2 rounded-xl vp-gradient text-xs font-bold text-white">Update Banner</button>
            </div>
          </div>
          <div class="flex items-center gap-6">
            <label class="flex items-center gap-2 cursor-pointer text-sm">
              <input id="chkCloudGpu" type="checkbox" onchange="saveGlobalSettings()" class="w-4 h-4 accent-[#22D3EE]" />
              <span>Cloud GPU Acceleration</span>
            </label>
            <label class="flex items-center gap-2 cursor-pointer text-sm">
              <input id="chkMaintenance" type="checkbox" onchange="saveGlobalSettings()" class="w-4 h-4 accent-amber-400" />
              <span>Maintenance Mode</span>
            </label>
          </div>
        </div>
      </div>

      <div id="featuresGrid" class="grid grid-cols-1 md:grid-cols-2 gap-4"></div>
    </section>

    <!-- 5. USAGE TELEMETRY TAB -->
    <section id="tab-usage" class="hidden space-y-6">
      <div>
        <h2 class="text-2xl font-extrabold">User Usage Telemetry & Filter Popularity</h2>
        <p class="text-sm text-[#9AA3B8]">Real-time tracking of every audio enhancement job, filter selection, and creator storage footprint.</p>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div class="vp-card p-6">
          <h3 class="text-base font-bold mb-4">Podcast Filter & DSP Module Popularity</h3>
          <div id="featureUsageBars" class="space-y-4"></div>
        </div>

        <div class="vp-card p-6">
          <h3 class="text-base font-bold mb-4">Top Creators by Audio Minutes Processed</h3>
          <div id="topCreatorsList" class="space-y-3"></div>
        </div>
      </div>
    </section>

  </main>

  <!-- MODAL: USER PROFILE INSPECTOR -->
  <div id="modalUserProfile" class="fixed inset-0 z-50 hidden bg-black/75 backdrop-blur-sm flex items-center justify-center p-4">
    <div class="vp-card max-w-2xl w-full p-6 space-y-5 max-h-[90vh] overflow-y-auto">
      <div class="flex items-start justify-between">
        <div class="flex items-center gap-4">
          <div id="profAvatar" class="w-14 h-14 rounded-full vp-gradient flex items-center justify-center text-xl font-black text-white">AR</div>
          <div>
            <h3 id="profName" class="text-xl font-extrabold">Alex Rivera</h3>
            <p id="profEmailDevice" class="text-xs text-[#9AA3B8]"></p>
            <p id="profJoinedActive" class="text-xs text-[#22D3EE] mt-0.5"></p>
          </div>
        </div>
        <button onclick="closeModal('modalUserProfile')" class="text-[#9AA3B8] hover:text-white text-xl font-bold">✕</button>
      </div>

      <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
        <div class="vp-surface-alt p-3 rounded-xl text-center">
          <div id="profMasters" class="text-lg font-extrabold text-[#22D3EE]">0</div>
          <div class="text-[11px] text-[#9AA3B8]">Masters</div>
        </div>
        <div class="vp-surface-alt p-3 rounded-xl text-center">
          <div id="profMinutes" class="text-lg font-extrabold text-[#22D3EE]">0m</div>
          <div class="text-[11px] text-[#9AA3B8]">Audio Mins</div>
        </div>
        <div class="vp-surface-alt p-3 rounded-xl text-center">
          <div id="profStorage" class="text-lg font-extrabold text-[#22D3EE]">0 MB</div>
          <div class="text-[11px] text-[#9AA3B8]">Storage Used</div>
        </div>
        <div class="vp-surface-alt p-3 rounded-xl text-center">
          <div id="profSpent" class="text-lg font-extrabold text-emerald-400">$0</div>
          <div class="text-[11px] text-[#9AA3B8]">Total Revenue</div>
        </div>
      </div>

      <div>
        <label class="text-xs font-bold uppercase text-[#9AA3B8]">Assign Subscription Plan (Instant Sync)</label>
        <div id="profPlanButtons" class="flex flex-wrap gap-2 mt-2"></div>
      </div>

      <div>
        <label class="text-xs font-bold uppercase text-[#9AA3B8]">Recent Audio Processing History</label>
        <div id="profJobsList" class="mt-2 space-y-1.5 text-xs bg-[#0B0D12] p-3.5 rounded-xl border border-[#2A3148]"></div>
      </div>

      <div class="flex justify-end gap-3 pt-2">
        <button id="profBtnToggleStatus" class="px-4 py-2 rounded-xl text-xs font-bold border"></button>
        <button id="profBtnDelete" class="px-4 py-2 rounded-xl bg-rose-500/20 border border-rose-500/40 text-rose-300 text-xs font-bold hover:bg-rose-500/30">Remove User Permanently</button>
      </div>
    </div>
  </div>

  <!-- MODAL: ADD NEW USER -->
  <div id="modalAddUser" class="fixed inset-0 z-50 hidden bg-black/75 backdrop-blur-sm flex items-center justify-center p-4">
    <div class="vp-card max-w-md w-full p-6 space-y-4">
      <div class="flex justify-between items-center">
        <h3 class="text-lg font-extrabold">Provision New Studio User</h3>
        <button onclick="closeModal('modalAddUser')" class="text-[#9AA3B8] hover:text-white">✕</button>
      </div>
      <input id="newUserName" type="text" placeholder="Full Creator Name" class="w-full px-3.5 py-2.5 rounded-xl vp-surface-alt text-sm" />
      <input id="newUserEmail" type="email" placeholder="Email Address" class="w-full px-3.5 py-2.5 rounded-xl vp-surface-alt text-sm" />
      <input id="newUserPassword" type="password" value="studio123" placeholder="Initial Password" class="w-full px-3.5 py-2.5 rounded-xl vp-surface-alt text-sm" />
      <select id="newUserRole" class="w-full px-3.5 py-2.5 rounded-xl vp-surface-alt text-sm">
        <option value="Podcaster">Podcaster</option>
        <option value="Vocalist">Vocalist</option>
        <option value="Voiceover">Voiceover</option>
        <option value="Streamer">Streamer</option>
      </select>
      <select id="newUserPlan" class="w-full px-3.5 py-2.5 rounded-xl vp-surface-alt text-sm"></select>
      <div class="flex justify-end gap-2 pt-2">
        <button onclick="closeModal('modalAddUser')" class="px-4 py-2 rounded-xl vp-surface-alt text-xs font-bold">Cancel</button>
        <button onclick="submitAddUser()" class="px-4 py-2 rounded-xl vp-gradient text-white text-xs font-bold">Create User in MongoDB</button>
      </div>
    </div>
  </div>

  <!-- MODAL: ADD SUBSCRIPTION PLAN -->
  <div id="modalAddPlan" class="fixed inset-0 z-50 hidden bg-black/75 backdrop-blur-sm flex items-center justify-center p-4">
    <div class="vp-card max-w-md w-full p-6 space-y-4">
      <div class="flex justify-between items-center">
        <h3 class="text-lg font-extrabold">Create Subscription Plan</h3>
        <button onclick="closeModal('modalAddPlan')" class="text-[#9AA3B8] hover:text-white">✕</button>
      </div>
      <input id="newPlanName" type="text" placeholder="Plan Title (e.g. Cinema Enterprise)" class="w-full px-3.5 py-2.5 rounded-xl vp-surface-alt text-sm" />
      <input id="newPlanBadge" type="text" value="ENTERPRISE" placeholder="Badge Text (e.g. BEST VALUE)" class="w-full px-3.5 py-2.5 rounded-xl vp-surface-alt text-sm" />
      <div class="grid grid-cols-2 gap-3">
        <input id="newPlanMonthly" type="number" step="0.01" value="49.99" placeholder="Monthly USD" class="w-full px-3.5 py-2.5 rounded-xl vp-surface-alt text-sm" />
        <input id="newPlanYearly" type="number" step="0.01" value="34.99" placeholder="Yearly/mo USD" class="w-full px-3.5 py-2.5 rounded-xl vp-surface-alt text-sm" />
      </div>
      <textarea id="newPlanDesc" rows="2" placeholder="Description shown in mobile app..." class="w-full px-3.5 py-2.5 rounded-xl vp-surface-alt text-sm">Unlimited neural DSP, custom theatrical bass & studio team seats.</textarea>
      <input id="newPlanPerks" type="text" value="Unlimited 48kHz WAV, Custom Theatrical Bass, Priority GPU Queue" placeholder="Comma-separated perks" class="w-full px-3.5 py-2.5 rounded-xl vp-surface-alt text-sm" />
      <label class="flex items-center gap-2 text-xs cursor-pointer">
        <input id="newPlanPopular" type="checkbox" class="w-4 h-4 accent-[#22D3EE]" />
        <span>Highlight with signature gradient as Most Popular</span>
      </label>
      <div class="flex justify-end gap-2 pt-2">
        <button onclick="closeModal('modalAddPlan')" class="px-4 py-2 rounded-xl vp-surface-alt text-xs font-bold">Cancel</button>
        <button onclick="submitAddPlan()" class="px-4 py-2 rounded-xl vp-gradient text-white text-xs font-bold">Publish to App</button>
      </div>
    </div>
  </div>

  <!-- MODAL: ADD NEW APP FEATURE / PODCAST FILTER -->
  <div id="modalAddFeature" class="fixed inset-0 z-50 hidden bg-black/75 backdrop-blur-sm flex items-center justify-center p-4">
    <div class="vp-card max-w-md w-full p-6 space-y-4">
      <div class="flex justify-between items-center">
        <h3 class="text-lg font-extrabold">Deploy New App Feature / Filter</h3>
        <button onclick="closeModal('modalAddFeature')" class="text-[#9AA3B8] hover:text-white">✕</button>
      </div>
      <input id="newFeatTitle" type="text" placeholder="Filter / Feature Name (e.g. Dolby Cinema Bass)" class="w-full px-3.5 py-2.5 rounded-xl vp-surface-alt text-sm" />
      <select id="newFeatCategory" class="w-full px-3.5 py-2.5 rounded-xl vp-surface-alt text-sm">
        <option value="Podcast Filter">Podcast Filter (Adds live chip + DSP curve in App)</option>
        <option value="DSP Engine">DSP Engine Module</option>
        <option value="Mastering">Mastering Chain</option>
      </select>
      <textarea id="newFeatDesc" rows="2" placeholder="Blurb shown under the filter chip in the mobile app..." class="w-full px-3.5 py-2.5 rounded-xl vp-surface-alt text-sm">Deep speaking-driven sub-bass with crisp cinema air</textarea>
      <div class="grid grid-cols-3 gap-2">
        <div>
          <label class="text-[11px] text-[#9AA3B8]">Bass (0–1.3)</label>
          <input id="newFeatBass" type="number" step="0.05" value="0.80" class="w-full px-3 py-2 rounded-xl vp-surface-alt text-sm mt-1" />
        </div>
        <div>
          <label class="text-[11px] text-[#9AA3B8]">Treble (0–1.0)</label>
          <input id="newFeatTreble" type="number" step="0.05" value="0.60" class="w-full px-3 py-2 rounded-xl vp-surface-alt text-sm mt-1" />
        </div>
        <div>
          <label class="text-[11px] text-[#9AA3B8]">Warmth (0–0.4)</label>
          <input id="newFeatWarmth" type="number" step="0.05" value="0.20" class="w-full px-3 py-2 rounded-xl vp-surface-alt text-sm mt-1" />
        </div>
      </div>
      <div>
        <label class="text-[11px] text-[#9AA3B8]">Stereo Acoustic Space</label>
        <select id="newFeatSpace" class="w-full px-3.5 py-2 rounded-xl vp-surface-alt text-sm mt-1">
          <option value="">Dry (Tight Mono)</option>
          <option value="theatre">Cinema Theatre Hall (Stereo 1.65s)</option>
          <option value="booth">Wide Broadcast Booth (Stereo 0.42s)</option>
        </select>
      </div>
      <label class="flex items-center gap-2 text-xs cursor-pointer">
        <input id="newFeatProOnly" type="checkbox" checked class="w-4 h-4 accent-[#22D3EE]" />
        <span>Gate to Pro Pass Subscribers</span>
      </label>
      <div class="flex justify-end gap-2 pt-2">
        <button onclick="closeModal('modalAddFeature')" class="px-4 py-2 rounded-xl vp-surface-alt text-xs font-bold">Cancel</button>
        <button onclick="submitAddFeature()" class="px-4 py-2 rounded-xl vp-gradient text-white text-xs font-bold">Deploy Live to App</button>
      </div>
    </div>
  </div>

  <!-- MODAL: RECORD SUBSCRIPTION PAYMENT -->
  <div id="modalRecordPayment" class="fixed inset-0 z-50 hidden bg-black/75 backdrop-blur-sm flex items-center justify-center p-4">
    <div class="vp-card max-w-md w-full p-6 space-y-4">
      <div class="flex justify-between items-center">
        <h3 class="text-lg font-extrabold">Record Subscription Payment</h3>
        <button onclick="closeModal('modalRecordPayment')" class="text-[#9AA3B8] hover:text-white">✕</button>
      </div>
      <input id="txUserName" type="text" placeholder="Customer Name" class="w-full px-3.5 py-2.5 rounded-xl vp-surface-alt text-sm" />
      <input id="txUserEmail" type="email" placeholder="Customer Email" class="w-full px-3.5 py-2.5 rounded-xl vp-surface-alt text-sm" />
      <input id="txPlanName" type="text" value="Studio AI Pro" placeholder="Plan Name" class="w-full px-3.5 py-2.5 rounded-xl vp-surface-alt text-sm" />
      <input id="txAmount" type="number" step="0.01" value="95.88" placeholder="Amount USD" class="w-full px-3.5 py-2.5 rounded-xl vp-surface-alt text-sm" />
      <div class="flex justify-end gap-2 pt-2">
        <button onclick="closeModal('modalRecordPayment')" class="px-4 py-2 rounded-xl vp-surface-alt text-xs font-bold">Cancel</button>
        <button onclick="submitRecordPayment()" class="px-4 py-2 rounded-xl vp-gradient text-white text-xs font-bold">Save Transaction</button>
      </div>
    </div>
  </div>

  <script>
    let STATE = { users: [], plans: [], features: [], transactions: [], settings: {}, metrics: {} };

    function fmtMoney(n) {
      return Number(n || 0).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    }

    function switchTab(tab) {
      ['overview', 'users', 'plans', 'features', 'usage'].forEach(t => {
        document.getElementById('tab-' + t).classList.toggle('hidden', t !== tab);
        const btn = document.getElementById('tabBtn-' + t);
        if (t === tab) {
          btn.className = 'tab-btn px-4 py-2 rounded-full text-sm font-bold vp-gradient text-white';
        } else {
          btn.className = 'tab-btn px-4 py-2 rounded-full text-sm font-semibold text-[#9AA3B8] hover:text-white bg-[#141824] border border-[#2A3148]';
        }
      });
    }

    function openModal(id) {
      if (id === 'modalAddUser') {
        const sel = document.getElementById('newUserPlan');
        sel.innerHTML = STATE.plans.map(p => `<option value="${p.name}">${p.name}</option>`).join('');
      }
      document.getElementById(id).classList.remove('hidden');
    }

    function closeModal(id) {
      document.getElementById(id).classList.add('hidden');
    }

    async function fetchState() {
      const res = await fetch('/api/admin/state');
      STATE = await res.json();
      renderAll();
    }

    function renderAll() {
      const m = STATE.metrics || {};
      document.getElementById('dbNameBadge').textContent = STATE.database || 'vocalpolish_studio';
      document.getElementById('kpiTotalRevenue').textContent = '$' + fmtMoney(m.total_revenue_usd);
      document.getElementById('kpiMrrSub').textContent = `Monthly Recurring Revenue (MRR): $${fmtMoney(m.mrr_usd)} / mo · ${m.total_subscribers || 0} Total Subscribers`;
      document.getElementById('kpiUsersCount').textContent = m.total_users || 0;
      document.getElementById('kpiUsersSub').textContent = `${m.active_users || 0} active · ${m.deactivated_users || 0} deactivated`;
      document.getElementById('kpiPlansCount').textContent = `${STATE.plans.length} Tiers`;
      document.getElementById('kpiPlansSub').textContent = `${STATE.plans.filter(p => p.enabled).length} enabled in mobile app`;
      document.getElementById('kpiFeaturesCount').textContent = `${STATE.features.filter(f => f.enabled).length}/${STATE.features.length}`;
      document.getElementById('kpiMastersCount').textContent = m.total_masters || 0;
      document.getElementById('kpiMinutesSub').textContent = `${m.total_minutes || 0} total studio minutes`;

      // Revenue Bars
      const revList = (STATE.settings && STATE.settings.monthly_revenue) || [];
      const maxRev = Math.max(1, ...revList.map(r => r.revenue_k));
      document.getElementById('revenueBarsContainer').innerHTML = revList.map(r => {
        const h = Math.max(18, Math.round((r.revenue_k / maxRev) * 125));
        return `<div class="flex-1 flex flex-col items-center">
          <span class="text-[11px] font-bold text-[#22D3EE] mb-1">$${r.revenue_k}k</span>
          <div style="height:${h}px" class="w-full rounded-t-lg vp-gradient"></div>
          <span class="text-xs text-[#9AA3B8] mt-1.5">${r.month}</span>
        </div>`;
      }).join('');

      // Transactions
      document.getElementById('transactionsList').innerHTML = STATE.transactions.map(t => `
        <div class="flex items-center justify-between p-3.5 rounded-xl vp-surface-alt">
          <div>
            <div class="text-sm font-bold">${t.user_name} <span class="text-xs font-normal text-[#9AA3B8]">(${t.user_email})</span></div>
            <div class="text-xs text-[#9AA3B8]">${t.plan_name} · ${t.billing_cycle} · ${t.method} · ${t.timestamp}</div>
          </div>
          <div class="text-sm font-extrabold text-emerald-400">+$${fmtMoney(t.amount_usd)}</div>
        </div>
      `).join('');

      // Global settings inputs
      if (STATE.settings) {
        document.getElementById('bannerInput').value = STATE.settings.broadcast_announcement || '';
        document.getElementById('chkCloudGpu').checked = !!STATE.settings.cloud_gpu_acceleration;
        document.getElementById('chkMaintenance').checked = !!STATE.settings.maintenance_mode;
      }

      renderUsers();
      renderPlans();
      renderFeatures();
      renderUsage();
    }

    function renderUsers() {
      const q = (document.getElementById('userSearchInput').value || '').toLowerCase();
      const f = document.getElementById('userStatusFilter').value;
      const list = STATE.users.filter(u => {
        const matchQ = !q || u.name.toLowerCase().includes(q) || u.email.toLowerCase().includes(q) || u.role.toLowerCase().includes(q) || u.plan_name.toLowerCase().includes(q);
        if (!matchQ) return false;
        if (f === 'active') return u.status === 'active';
        if (f === 'deactivated') return u.status !== 'active';
        if (f === 'pro') return u.plan_name !== 'Creator Starter';
        return true;
      });

      document.getElementById('usersGrid').innerHTML = list.map(u => {
        const isAct = u.status === 'active';
        const initials = u.name.split(' ').map(s => s[0]).join('').slice(0, 2).toUpperCase();
        return `<div class="vp-card p-5 flex flex-col justify-between gap-4">
          <div class="flex items-start justify-between gap-3">
            <div class="flex items-center gap-3.5">
              <div class="w-12 h-12 rounded-full ${isAct ? 'vp-gradient' : 'bg-[#1C2233]'} flex items-center justify-center font-extrabold text-white">${initials}</div>
              <div>
                <div class="flex items-center gap-2">
                  <span class="font-extrabold text-base">${u.name}</span>
                  <span class="text-[10px] px-2 py-0.5 rounded-full font-extrabold ${isAct ? 'bg-emerald-500/20 text-emerald-300' : 'bg-rose-500/20 text-rose-300'}">${u.status.toUpperCase()}</span>
                </div>
                <div class="text-xs text-[#9AA3B8]">${u.email} · ${u.role}</div>
                <div class="text-xs text-[#22D3EE] mt-1">Plan: <b>${u.plan_name}</b> · ${u.masters_count} masters (${u.minutes_processed}m)</div>
              </div>
            </div>
            <span class="text-xs font-mono text-[#9AA3B8]">${u.id}</span>
          </div>
          <div class="flex items-center justify-between pt-3 border-t border-[#2A3148] text-xs">
            <span class="text-[#9AA3B8]">LTV: <b class="text-emerald-400">$${fmtMoney(u.total_spent_usd)}</b> · Fav: ${u.favorite_filter}</span>
            <div class="flex items-center gap-2">
              <button onclick="inspectUser('${u.id}')" class="px-3 py-1.5 rounded-lg vp-surface-alt hover:border-[#22D3EE] font-bold">Profile</button>
              <button onclick="toggleUserStatus('${u.id}')" class="px-3 py-1.5 rounded-lg font-bold ${isAct ? 'bg-amber-500/20 text-amber-300' : 'bg-emerald-500/20 text-emerald-300'}">${isAct ? 'Deactivate' : 'Activate'}</button>
              <button onclick="deleteUser('${u.id}')" class="px-2.5 py-1.5 rounded-lg bg-rose-500/20 text-rose-300 font-bold hover:bg-rose-500/30">✕</button>
            </div>
          </div>
        </div>`;
      }).join('');
    }

    function inspectUser(uid) {
      const u = STATE.users.find(x => x.id === uid);
      if (!u) return;
      document.getElementById('profAvatar').textContent = u.name.split(' ').map(s => s[0]).join('').slice(0, 2).toUpperCase();
      document.getElementById('profName').textContent = `${u.name} (${u.id})`;
      document.getElementById('profEmailDevice').textContent = `${u.email} · ${u.device_model}`;
      document.getElementById('profJoinedActive').textContent = `Joined ${u.joined_date} · Last active: ${u.last_active}`;
      document.getElementById('profMasters').textContent = u.masters_count;
      document.getElementById('profMinutes').textContent = u.minutes_processed + 'm';
      document.getElementById('profStorage').textContent = Math.round(u.storage_used_mb) + ' MB';
      document.getElementById('profSpent').textContent = '$' + fmtMoney(u.total_spent_usd);

      document.getElementById('profPlanButtons').innerHTML = STATE.plans.map(p => `
        <button onclick="changeUserPlan('${u.id}', '${p.name}')" class="px-3.5 py-1.5 rounded-full text-xs font-bold ${u.plan_name === p.name ? 'vp-gradient text-white' : 'vp-surface-alt text-[#9AA3B8] hover:text-white'}">${p.name}</button>
      `).join('');

      const jobs = u.recent_jobs || [];
      document.getElementById('profJobsList').innerHTML = jobs.length
        ? jobs.map(j => `<div class="flex items-center gap-2"><span class="text-emerald-400">✓</span><span>${j}</span></div>`).join('')
        : `<div class="text-[#9AA3B8]">No audio jobs recorded yet.</div>`;

      const btnSt = document.getElementById('profBtnToggleStatus');
      const isAct = u.status === 'active';
      btnSt.textContent = isAct ? 'Deactivate Account' : 'Reactivate Account';
      btnSt.className = `px-4 py-2 rounded-xl text-xs font-bold border ${isAct ? 'border-amber-500/40 text-amber-300 bg-amber-500/10' : 'border-emerald-500/40 text-emerald-300 bg-emerald-500/10'}`;
      btnSt.onclick = async () => { await toggleUserStatus(u.id); closeModal('modalUserProfile'); };

      const btnDel = document.getElementById('profBtnDelete');
      btnDel.onclick = async () => { await deleteUser(u.id); closeModal('modalUserProfile'); };

      openModal('modalUserProfile');
    }

    function renderPlans() {
      document.getElementById('plansGrid').innerHTML = STATE.plans.map(p => `
        <div class="vp-card p-6 flex flex-col justify-between gap-4 ${p.popular ? 'border-[#22D3EE] vp-glow' : ''}">
          <div>
            <div class="flex items-center justify-between gap-2">
              <span class="text-xs font-extrabold px-2.5 py-1 rounded-full ${p.popular ? 'vp-gradient text-white' : 'vp-surface-alt text-[#9AA3B8]'}">${p.badge}</span>
              <label class="flex items-center gap-1.5 text-xs cursor-pointer">
                <input type="checkbox" ${p.enabled ? 'checked' : ''} onchange="togglePlan('${p.id}')" class="w-4 h-4 accent-[#22D3EE]" />
                <span>${p.enabled ? 'Enabled' : 'Hidden'}</span>
              </label>
            </div>
            <h3 class="text-xl font-extrabold mt-3">${p.name}</h3>
            <div class="mt-2 flex items-baseline gap-2">
              <span class="text-3xl font-black vp-text-gradient">${p.monthly_price === 0 ? 'Free' : '$' + p.monthly_price.toFixed(2)}</span>
              <span class="text-xs text-[#9AA3B8]">${p.yearly_price > 0 ? `/mo ($${p.yearly_price.toFixed(2)}/mo yearly)` : 'forever'}</span>
            </div>
            <p class="text-xs text-[#9AA3B8] mt-2">${p.description}</p>
            <div class="mt-4 space-y-1.5">
              ${(p.perks || []).map(pk => `<div class="text-xs flex items-center gap-2"><span class="text-emerald-400">✓</span><span>${pk}</span></div>`).join('')}
            </div>
          </div>
          <div class="pt-3 border-t border-[#2A3148] flex items-center justify-between text-xs">
            <span class="text-emerald-400 font-bold">${p.active_subscribers} active subscribers</span>
            ${p.id !== 'plan_starter' ? `<button onclick="deletePlan('${p.id}')" class="text-rose-400 hover:underline font-bold">Remove Tier</button>` : ''}
          </div>
        </div>
      `).join('');
    }

    function renderFeatures() {
      document.getElementById('featuresGrid').innerHTML = STATE.features.map(f => `
        <div class="vp-card p-5 flex flex-col justify-between gap-4">
          <div class="flex items-start justify-between gap-3">
            <div>
              <div class="flex items-center gap-2">
                <span class="text-base font-extrabold">${f.title}</span>
                <span class="text-[11px] px-2.5 py-0.5 rounded-full vp-surface-alt text-[#22D3EE] font-bold">${f.category}</span>
              </div>
              <p class="text-xs text-[#9AA3B8] mt-1">${f.description}</p>
            </div>
            <label class="flex items-center gap-1.5 text-xs cursor-pointer">
              <input type="checkbox" ${f.enabled ? 'checked' : ''} onchange="toggleFeature('${f.id}')" class="w-4 h-4 accent-[#22D3EE]" />
              <span>${f.enabled ? 'Live' : 'Off'}</span>
            </label>
          </div>
          <div class="px-3 py-2 rounded-xl bg-[#0B0D12] border border-[#2A3148] font-mono text-xs text-[#22D3EE]">
            DSP: ${f.dsp_params}
          </div>
          <div class="flex items-center justify-between text-xs pt-2 border-t border-[#2A3148]">
            <span class="text-[#9AA3B8]"><b>${f.usage_count}</b> studio runs</span>
            <div class="flex items-center gap-2">
              <button onclick="toggleFeaturePro('${f.id}')" class="px-3 py-1 rounded-full font-extrabold text-[11px] ${f.pro_only ? 'vp-gradient text-white' : 'vp-surface-alt text-[#9AA3B8]'}">
                ${f.pro_only ? 'PRO TIER ONLY' : 'FREE FOR ALL'}
              </button>
              <button onclick="deleteFeature('${f.id}')" class="text-rose-400 hover:underline font-bold ml-2">Delete</button>
            </div>
          </div>
        </div>
      `).join('');
    }

    function renderUsage() {
      const maxRuns = Math.max(1, ...STATE.features.map(f => f.usage_count));
      document.getElementById('featureUsageBars').innerHTML = STATE.features.map(f => {
        const pct = Math.min(100, Math.max(4, Math.round((f.usage_count / maxRuns) * 100)));
        return `<div>
          <div class="flex justify-between text-xs mb-1">
            <span class="font-bold">${f.title} <span class="text-[#9AA3B8] font-normal">(${f.category})</span></span>
            <span class="text-[#22D3EE] font-bold">${f.usage_count.toLocaleString()} runs</span>
          </div>
          <div class="w-full h-2.5 rounded-full bg-[#1C2233] overflow-hidden">
            <div style="width:${pct}%" class="h-full vp-gradient"></div>
          </div>
        </div>`;
      }).join('');

      const sortedUsers = [...STATE.users].sort((a, b) => b.minutes_processed - a.minutes_processed);
      document.getElementById('topCreatorsList').innerHTML = sortedUsers.map(u => `
        <div class="flex items-center justify-between p-3 rounded-xl vp-surface-alt">
          <div>
            <div class="text-sm font-bold">${u.name} <span class="text-xs text-[#22D3EE]">(${u.plan_name})</span></div>
            <div class="text-xs text-[#9AA3B8]">Fav Filter: ${u.favorite_filter} · ${u.device_model}</div>
          </div>
          <div class="text-right">
            <div class="text-sm font-extrabold text-[#22D3EE]">${u.minutes_processed} mins</div>
            <div class="text-[11px] text-[#9AA3B8]">${u.masters_count} masters</div>
          </div>
        </div>
      `).join('');
    }

    // ── API Actions ──
    async function toggleUserStatus(uid) {
      await fetch(`/api/admin/users/${uid}/toggle-status`, { method: 'POST' });
      await fetchState();
    }

    async function changeUserPlan(uid, planName) {
      await fetch(`/api/admin/users/${uid}/plan`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ plan_name: planName })
      });
      await fetchState();
      inspectUser(uid);
    }

    async function deleteUser(uid) {
      if (!confirm('Remove this user permanently from MongoDB?')) return;
      await fetch(`/api/admin/users/${uid}`, { method: 'DELETE' });
      await fetchState();
    }

    async function submitAddUser() {
      const name = document.getElementById('newUserName').value.trim();
      const email = document.getElementById('newUserEmail').value.trim();
      const password = document.getElementById('newUserPassword').value;
      const role = document.getElementById('newUserRole').value;
      const plan_name = document.getElementById('newUserPlan').value;
      if (!name || !email) return alert('Name and email are required');
      await fetch('/api/admin/users', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name, email, password, role, plan_name })
      });
      closeModal('modalAddUser');
      await fetchState();
    }

    async function submitAddPlan() {
      const name = document.getElementById('newPlanName').value.trim();
      const badge = document.getElementById('newPlanBadge').value.trim();
      const monthly_price = parseFloat(document.getElementById('newPlanMonthly').value || 0);
      const yearly_price = parseFloat(document.getElementById('newPlanYearly').value || 0);
      const description = document.getElementById('newPlanDesc').value.trim();
      const perks = document.getElementById('newPlanPerks').value.split(',').map(s => s.trim()).filter(Boolean);
      const popular = document.getElementById('newPlanPopular').checked;
      if (!name) return alert('Plan name required');
      await fetch('/api/admin/plans', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name, badge, monthly_price, yearly_price, description, perks, popular })
      });
      closeModal('modalAddPlan');
      await fetchState();
    }

    async function togglePlan(pid) {
      await fetch(`/api/admin/plans/${pid}/toggle`, { method: 'POST' });
      await fetchState();
    }

    async function deletePlan(pid) {
      if (!confirm('Delete this subscription tier from MongoDB?')) return;
      await fetch(`/api/admin/plans/${pid}`, { method: 'DELETE' });
      await fetchState();
    }

    async function submitAddFeature() {
      const title = document.getElementById('newFeatTitle').value.trim();
      const category = document.getElementById('newFeatCategory').value;
      const description = document.getElementById('newFeatDesc').value.trim();
      const bass = parseFloat(document.getElementById('newFeatBass').value || 0.5);
      const treble = parseFloat(document.getElementById('newFeatTreble').value || 0.4);
      const warmth = parseFloat(document.getElementById('newFeatWarmth').value || 0.15);
      const space = document.getElementById('newFeatSpace').value;
      const pro_only = document.getElementById('newFeatProOnly').checked;
      if (!title) return alert('Feature title required');
      await fetch('/api/admin/features', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ title, category, description, bass, treble, warmth, space, pro_only })
      });
      closeModal('modalAddFeature');
      await fetchState();
    }

    async function toggleFeature(fid) {
      await fetch(`/api/admin/features/${fid}/toggle`, { method: 'POST' });
      await fetchState();
    }

    async function toggleFeaturePro(fid) {
      await fetch(`/api/admin/features/${fid}/toggle-pro`, { method: 'POST' });
      await fetchState();
    }

    async function deleteFeature(fid) {
      if (!confirm('Delete this feature from MongoDB?')) return;
      await fetch(`/api/admin/features/${fid}`, { method: 'DELETE' });
      await fetchState();
    }

    async function saveGlobalSettings() {
      const broadcast_announcement = document.getElementById('bannerInput').value.trim();
      const cloud_gpu_acceleration = document.getElementById('chkCloudGpu').checked;
      const maintenance_mode = document.getElementById('chkMaintenance').checked;
      await fetch('/api/admin/settings', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ broadcast_announcement, cloud_gpu_acceleration, maintenance_mode })
      });
      await fetchState();
    }

    async function submitRecordPayment() {
      const user_name = document.getElementById('txUserName').value.trim();
      const user_email = document.getElementById('txUserEmail').value.trim();
      const plan_name = document.getElementById('txPlanName').value.trim();
      const amount_usd = parseFloat(document.getElementById('txAmount').value || 0);
      if (!user_name || !amount_usd) return;
      await fetch('/api/admin/transactions', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ user_name, user_email, plan_name, amount_usd, billing_cycle: 'Yearly', method: 'Admin Manual' })
      });
      closeModal('modalRecordPayment');
      await fetchState();
    }

    fetchState();
    setInterval(fetchState, 6000);
  </script>
</body>
</html>
"""
