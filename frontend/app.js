let currentUserId = null;
let currentUserName = "";
let authToken = null;
let categories = [];

const $ = (sel) => document.querySelector(sel);
const $$ = (sel) => [...document.querySelectorAll(sel)];
const escapeHtml = (value) => String(value ?? "").replace(/[&<>"']/g, (ch) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[ch]);

async function api(path, options = {}) {
  let res;
  try {
    const headers = { "Content-Type": "application/json", ...options.headers };
    if (authToken) headers.Authorization = `Bearer ${authToken}`;
    res = await fetch(path, { ...options, headers });
  } catch {
    throw new Error("Could not reach the server. Check that the app is running and retry.");
  }
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.detail || `Request failed (${res.status})`);
  return data;
}

function toast(message, kind = "success") {
  const node = document.createElement("div");
  node.className = `toast ${kind}`;
  node.setAttribute("role", "status");
  node.textContent = message;
  $("#toastRegion").append(node);
  window.setTimeout(() => node.remove(), 3800);
}

function setLoadState(container, state, retry) {
  if (state === "loading") container.innerHTML = '<div class="load-state" role="status"><span class="spinner"></span> Loading…</div>';
  if (state === "error" || typeof state === "object") {
    container.replaceChildren();
    const box = document.createElement("div");
    box.className = "load-state error-state";
    const message = document.createElement("span");
    message.textContent = (typeof state === "object" && state.message) || "Could not load this section.";
    const button = document.createElement("button");
    button.type = "button";
    button.textContent = "Retry";
    button.addEventListener("click", retry);
    box.append(message, button);
    container.append(box);
  }
}

function updateHeader(balance = null) {
  $("#whoName").textContent = currentUserName || "Student";
  $("#whoBalance").textContent = balance === null ? "" : `Balance: ₹${balance}`;
}

async function loadAccountBalance() {
  const host = $("#accountLoadError");
  host.replaceChildren();
  try {
    const wallet = await api(`/api/wallet/${currentUserId}`);
    updateHeader(wallet.balance);
  } catch (error) {
    const box = document.createElement("div"); box.className = "inline-error";
    const message = document.createElement("span"); message.textContent = `Balance could not be refreshed: ${error.message}`;
    const retry = document.createElement("button"); retry.type = "button"; retry.textContent = "Retry"; retry.addEventListener("click", loadAccountBalance);
    box.append(message, retry); host.append(box);
  }
}

function showGate(tab = "signin") {
  $("#authGate").hidden = false;
  $("#appShell").hidden = true;
  $$(".auth-tab").forEach((button) => button.classList.toggle("active", button.dataset.authTab === tab));
  $("#signinPane").hidden = tab !== "signin";
  $("#createPane").hidden = tab !== "create";
  $("#claimPane").hidden = tab !== "claim";
}

function signIn(session) {
  currentUserId = Number(session.user_id);
  currentUserName = session.full_name;
  authToken = session.access_token;
  sessionStorage.setItem("campusAuth", JSON.stringify({ access_token: authToken, user_id: currentUserId, full_name: currentUserName }));
  $("#authGate").classList.add("leaving");
  window.setTimeout(() => {
    $("#authGate").hidden = true;
    $("#authGate").classList.remove("leaving");
    $("#appShell").hidden = false;
    updateHeader();
    bootApp();
  }, 180);
}

function logout() {
  sessionStorage.removeItem("campusAuth");
  sessionStorage.removeItem("campusUser");
  currentUserId = null;
  currentUserName = "";
  authToken = null;
  $("#authGate").hidden = false;
  $("#appShell").hidden = true;
  showGate("signin");
}

$("#signOut").addEventListener("click", logout);
$$(".auth-tab").forEach((button) => button.addEventListener("click", () => showGate(button.dataset.authTab)));

$("#signinForm").addEventListener("submit", async (event) => {
  event.preventDefault();
  $("#signinError").textContent = "";
  const submit = $("#signinSubmit"); submit.disabled = true;
  try {
    const session = await api("/api/auth/login", { method: "POST", body: JSON.stringify({ reg_no: $("#signinRegNo").value.trim(), password: $("#signinPassword").value }) });
    signIn(session);
  } catch (error) {
    $("#signinError").textContent = error.message;
  } finally { submit.disabled = false; }
});

$("#claimForm").addEventListener("submit", async (event) => {
  event.preventDefault();
  $("#claimError").textContent = "";
  const submit = $("#claimSubmit"); submit.disabled = true;
  try {
    const session = await api("/api/auth/set-password", { method: "POST", body: JSON.stringify({ reg_no: $("#claimRegNo").value.trim(), email: $("#claimEmail").value.trim(), phone: $("#claimPhone").value.trim(), password: $("#claimPassword").value }) });
    signIn(session);
  } catch (error) {
    $("#claimError").textContent = error.message;
  } finally { submit.disabled = false; }
});

async function loadCategories() {
  const host = $("#categoryLoadState");
  host.replaceChildren();
  $("#sellCategoryError").replaceChildren();
  try {
    categories = await api("/api/categories");
    const opts = categories.map((c) => `<option value="${Number(c.category_id)}">${escapeHtml(c.category_name)}</option>`).join("");
    $("#sellCategory").innerHTML = opts;
    const filter = $("#categoryFilter");
    filter.innerHTML = '<option value="">All categories</option>' + opts;
    return categories;
  } catch (error) {
    const box = document.createElement("div"); box.className = "inline-error";
    const message = document.createElement("span"); message.textContent = `Categories unavailable: ${error.message}`;
    const retry = document.createElement("button"); retry.type = "button"; retry.textContent = "Retry"; retry.addEventListener("click", loadCategories);
    box.append(message, retry); host.append(box);
    const sellError = document.createElement("div"); sellError.className = "inline-error";
    const sellMessage = document.createElement("span"); sellMessage.textContent = `Categories unavailable: ${error.message}`;
    const sellRetry = document.createElement("button"); sellRetry.type = "button"; sellRetry.textContent = "Retry"; sellRetry.addEventListener("click", loadCategories);
    sellError.append(sellMessage, sellRetry); $("#sellCategoryError").append(sellError);
    throw error;
  }
}

async function loadItems() {
  const grid = $("#itemGrid");
  setLoadState(grid, "loading");
  try {
    const catId = $("#categoryFilter").value;
    const items = await api(`/api/items?status=AVAILABLE${catId ? `&category_id=${encodeURIComponent(catId)}` : ""}`);
    grid.innerHTML = items.map((it) => `
      <article class="card item-card">
        <div class="item-topline"><span class="badge AVAILABLE">AVAILABLE</span><span class="item-condition">${escapeHtml(it.item_condition)}</span></div>
        <h3>${escapeHtml(it.title)}</h3>
        <div class="price">₹${escapeHtml(it.price)}</div>
        <p class="item-description">${escapeHtml(it.description || "No description provided.")}</p>
        <div class="meta">${escapeHtml(it.category_name)}</div>
        <div class="meta">Seller: ${escapeHtml(it.seller_name)} · ${Number(it.seller_rating || 0).toFixed(2)}★</div>` +
        ((it.seller_phone || it.seller_hostel) ? `\n        <div class="meta seller-contact">${it.seller_phone ? `📞 ${escapeHtml(it.seller_phone)}` : ""}${it.seller_phone && it.seller_hostel ? " · " : ""}${it.seller_hostel ? `🏠 ${escapeHtml(it.seller_hostel)}` : ""}</div>` : "") + `
        <button type="button" onclick="reserveItem(${Number(it.item_id)})">Reserve</button>
      </article>`).join("") || '<p class="empty-state">No items match.</p>';
  } catch (error) {
    grid.innerHTML = "";
    setLoadState(grid, { message: `Items could not be loaded: ${error.message}` }, loadItems);
  }
}

window.reserveItem = async (itemId) => {
  try {
    const result = await api(`/api/items/${itemId}/reserve`, { method: "POST", body: JSON.stringify({ buyer_id: currentUserId }) });
    toast(`Reserved! Transaction #${result.txn_id} is held in escrow.`);
    await Promise.allSettled([loadItems(), loadAccountBalance()]);
  } catch (error) { toast(error.message, "error"); }
};
$("#refreshItems").addEventListener("click", loadItems);
$("#categoryFilter").addEventListener("change", loadItems);

$("#sellForm").addEventListener("submit", async (event) => {
  event.preventDefault();
  try {
    await api("/api/items", { method: "POST", body: JSON.stringify({ seller_id: currentUserId, category_id: Number($("#sellCategory").value), title: $("#sellTitle").value, description: $("#sellDescription").value, price: Number($("#sellPrice").value), item_condition: $("#sellCondition").value, days_valid: Number($("#sellDays").value) }) });
    event.target.reset(); toast("Your item is listed."); await Promise.allSettled([loadItems(), loadMyItems()]);
  } catch (error) { toast(error.message, "error"); }
});

async function loadMyItems() {
  const tbody = $("#mineTable tbody"); tbody.innerHTML = '<tr><td colspan="5"><span class="spinner"></span> Loading listings…</td></tr>';
  try {
    const items = await api(`/api/items/mine?seller_id=${currentUserId}`);
    tbody.innerHTML = items.map((it) => `<tr><td>${escapeHtml(it.title)}</td><td>₹${escapeHtml(it.price)}</td><td><span class="badge ${escapeHtml(it.status)}">${escapeHtml(it.status)}</span></td><td>${escapeHtml(fmt(it.listed_at))}</td><td>${escapeHtml(fmt(it.expires_at))}</td></tr>`).join("") || '<tr><td colspan="5">No listings yet.</td></tr>';
  } catch (error) { renderTableError(tbody, 5, `Listings could not be loaded: ${error.message}`, loadMyItems); }
}

function renderTableError(tbody, columns, message, retry) {
  tbody.replaceChildren(); const row = document.createElement("tr"); const cell = document.createElement("td"); cell.colSpan = columns;
  const box = document.createElement("div"); box.className = "inline-error"; const text = document.createElement("span"); text.textContent = message;
  const button = document.createElement("button"); button.type = "button"; button.textContent = "Retry"; button.addEventListener("click", retry); box.append(text, button); cell.append(box); row.append(cell); tbody.append(row);
}

async function loadEscrow() {
  const tbody = $("#escrowTable tbody"), role = $('input[name="role"]:checked').value;
  tbody.innerHTML = '<tr><td colspan="5"><span class="spinner"></span> Loading escrow…</td></tr>';
  try {
    const txns = await api(`/api/escrow/mine?user_id=${currentUserId}&role=${role}`);
    tbody.innerHTML = txns.map((txn) => {
      let action = "";
      if (txn.escrow_status === "HELD" && role === "seller") action = `<button onclick="deliver(${Number(txn.txn_id)})">Confirm delivery</button> <button class="secondary" onclick="refund(${Number(txn.txn_id)})">Reject reservation</button>`;
      else if (txn.escrow_status === "HELD" && role === "buyer") action = `<button class="secondary" onclick="refund(${Number(txn.txn_id)})">Cancel / refund</button>`;
      else if (txn.escrow_status === "RELEASED" && role === "buyer") action = txn.review_rating ? `<span class="meta">Reviewed (${Number(txn.review_rating)}★)</span>` : `<button onclick="reviewTxn(${Number(txn.txn_id)})">Leave review</button>`; else if (txn.escrow_status === "RELEASED" && role === "seller" && txn.review_rating) action = `<span class="meta">Rated ${Number(txn.review_rating)}★</span>`;
      // Show counterparty contact info under item name
      let contactInfo = "";
      if (txn.counterparty_name) {
        const label = role === "buyer" ? "Seller" : "Buyer";
        const isHeld = txn.escrow_status === "HELD";
        const parts = [`<strong>${escapeHtml(label)}:</strong> ${escapeHtml(txn.counterparty_name)}`];
        if (txn.counterparty_phone) parts.push(`📞 ${escapeHtml(txn.counterparty_phone)}`);
        if (txn.counterparty_hostel) parts.push(`🏠 ${escapeHtml(txn.counterparty_hostel)}`);
        contactInfo = `<div class="contact-info ${isHeld ? 'contact-held' : ''}">${parts.join(" · ")}</div>`;
      }
      return `<tr><td>${escapeHtml(txn.title)}${contactInfo}</td><td>₹${escapeHtml(txn.amount)}</td><td><span class="badge ${escapeHtml(txn.escrow_status)}">${escapeHtml(txn.escrow_status)}</span></td><td>${escapeHtml(fmt(txn.created_at))}</td><td>${action}</td></tr>`;
    }).join("") || '<tr><td colspan="5">Nothing here yet.</td></tr>';
  } catch (error) { renderTableError(tbody, 5, `Escrow could not be loaded: ${error.message}`, loadEscrow); }
}
$$('input[name="role"]').forEach((input) => input.addEventListener("change", loadEscrow));

async function refreshAccountData() { await Promise.allSettled([loadAccountBalance()]); }
window.deliver = async (txnId) => {
  try { await api(`/api/escrow/${txnId}/deliver`, { method: "POST", body: JSON.stringify({ user_id: currentUserId }) }); toast("Delivery confirmed. Funds released to the seller."); await Promise.allSettled([loadEscrow(), refreshAccountData()]); }
  catch (error) { toast(error.message, "error"); }
};
window.refund = async (txnId) => {
  try { await api(`/api/escrow/${txnId}/refund`, { method: "POST", body: JSON.stringify({ user_id: currentUserId }) }); toast("Reservation cancelled and funds refunded."); await Promise.allSettled([loadEscrow(), loadItems(), refreshAccountData()]); }
  catch (error) { toast(error.message, "error"); }
};

let selectedRating = 5;
function openReview(txnId) {
  $("#reviewTxnId").value = txnId;
  selectedRating = 5;
  $$(".star-button").forEach((button) => { button.classList.toggle("selected", Number(button.dataset.rating) <= selectedRating); button.setAttribute("aria-pressed", Number(button.dataset.rating) <= selectedRating ? "true" : "false"); });
  $("#reviewComments").value = "";
  $("#reviewDialog").showModal();
}
window.reviewTxn = openReview;
$$('.star-button').forEach((button) => button.addEventListener("click", () => {
  selectedRating = Number(button.dataset.rating);
  $$(".star-button").forEach((star) => { const on = Number(star.dataset.rating) <= selectedRating; star.classList.toggle("selected", on); star.setAttribute("aria-pressed", on ? "true" : "false"); });
}));
$("#reviewForm").addEventListener("submit", async (event) => {
  event.preventDefault();
  try {
    await api("/api/reviews", { method: "POST", body: JSON.stringify({ txn_id: Number($("#reviewTxnId").value), rating: selectedRating, comments: $("#reviewComments").value.trim() || null }) });
    $("#reviewDialog").close(); toast("Thanks for leaving a review."); await loadEscrow();
  } catch (error) { toast(error.message, "error"); }
});
$("#closeReview").addEventListener("click", () => $("#reviewDialog").close());
$("#cancelReview").addEventListener("click", () => $("#reviewDialog").close());

async function loadWallet() {
  const tbody = $("#ledgerTable tbody"); tbody.innerHTML = '<tr><td colspan="4"><span class="spinner"></span> Loading wallet…</td></tr>';
  try {
    const wallet = await api(`/api/wallet/${currentUserId}`);
    $("#whoBalance").textContent = `Balance: ₹${wallet.balance}`;
    const history = wallet.history || [];
    tbody.innerHTML = history.map((entry) => `<tr><td>${escapeHtml(entry.entry_type)}</td><td>₹${escapeHtml(entry.amount)}</td><td>${escapeHtml(entry.txn_id ?? "-")}</td><td>${escapeHtml(fmt(entry.created_at))}</td></tr>`).join("") || '<tr><td colspan="4">No activity yet.</td></tr>';
  } catch (error) { renderTableError(tbody, 4, `Wallet could not be loaded: ${error.message}`, loadWallet); }
}
$("#topupForm").addEventListener("submit", async (event) => {
  event.preventDefault();
  try {
    await api("/api/wallet/topup", { method: "POST", body: JSON.stringify({ user_id: currentUserId, amount: Number($("#topupAmount").value) }) });
    event.target.reset(); toast("Funds added to your wallet."); await Promise.allSettled([loadWallet(), loadAccountBalance()]);
  } catch (error) { toast(error.message, "error"); }
});

const signupFields = ["suRegNo", "suName", "suEmail", "suPhone", "suHostel", "suPassword"];
function clearSignupErrors() { signupFields.forEach((id) => { $(`#${id}Error`).textContent = ""; $(`#${id}`).removeAttribute("aria-invalid"); }); $("#signupFormError").textContent = ""; }
function setSignupError(id, message) { $(`#${id}Error`).textContent = message; $(`#${id}`).setAttribute("aria-invalid", "true"); }
async function createAccount(event) {
  event.preventDefault(); clearSignupErrors(); $("#duplicateSignIn").hidden = true;
  const payload = { reg_no: $("#suRegNo").value.trim(), full_name: $("#suName").value.trim(), email: $("#suEmail").value.trim(), phone: $("#suPhone").value.trim(), hostel_block: $("#suHostel").value.trim(), password: $("#suPassword").value };
  let valid = true;
  if (!payload.reg_no) { setSignupError("suRegNo", "Registration number is required."); valid = false; }
  if (!payload.full_name) { setSignupError("suName", "Full name is required."); valid = false; }
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(payload.email)) { setSignupError("suEmail", "Enter a valid email address."); valid = false; }
  if (!payload.phone) { setSignupError("suPhone", "Phone is required."); valid = false; }
  if (!payload.hostel_block) { setSignupError("suHostel", "Hostel block is required."); valid = false; }
  if (payload.password.length < 8) { setSignupError("suPassword", "Use at least 8 characters."); valid = false; }
  if (!valid) return;
  const submit = $("#createAccountSubmit"); submit.disabled = true;
  try {
    const result = await api("/api/auth/signup", { method: "POST", body: JSON.stringify(payload) });
    signIn(result);
    toast("Your account is ready.");
  } catch (error) {
    const detail = error.message;
    if (/ORA-00001|already (exists|in use)/i.test(detail)) {
      $("#signupFormError").textContent = "That registration number or email is already registered. Sign in if the account is yours, or use different values.";
      $("#duplicateSignIn").hidden = false;
    } else if (/email/i.test(detail)) setSignupError("suEmail", detail);
    else if (/reg|registration/i.test(detail)) setSignupError("suRegNo", detail);
    else if (/name/i.test(detail)) setSignupError("suName", detail);
    else $("#signupFormError").textContent = detail;
  } finally { submit.disabled = false; }
}
$("#createForm").addEventListener("submit", createAccount);
$("#duplicateSignIn").addEventListener("click", () => showGate("signin"));

function fmt(timestamp) { if (!timestamp) return "-"; const date = new Date(timestamp); return Number.isNaN(date.getTime()) ? String(timestamp) : date.toLocaleString(); }

$$('.tab-btn').forEach((button) => button.addEventListener("click", () => {
  $$(".tab-btn").forEach((tab) => tab.classList.remove("active"));
  $$(".tab-panel").forEach((panel) => panel.classList.remove("active"));
  button.classList.add("active"); $(`#tab-${button.dataset.tab}`).classList.add("active");
  if (button.dataset.tab === "mine") loadMyItems();
  if (button.dataset.tab === "escrow") loadEscrow();
  if (button.dataset.tab === "wallet") loadWallet();
}));

async function bootApp() {
  await Promise.allSettled([loadAccountBalance(), loadCategories(), loadItems()]);
}

(async function init() {
  let session = null;
  try { session = JSON.parse(sessionStorage.getItem("campusAuth") || "null"); } catch { sessionStorage.removeItem("campusAuth"); }
  if (session?.access_token) {
    authToken = session.access_token;
    try {
      const account = await api("/api/auth/me");
      currentUserId = account.user_id; currentUserName = account.full_name;
      $("#authGate").hidden = true; $("#appShell").hidden = false; updateHeader(); bootApp();
      return;
    } catch { sessionStorage.removeItem("campusAuth"); authToken = null; }
  }
  showGate("signin");
})();
