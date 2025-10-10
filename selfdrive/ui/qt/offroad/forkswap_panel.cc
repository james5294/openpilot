#include "selfdrive/ui/qt/offroad/forkswap_panel.h"

#include <QBrush>
#include <QFrame>
#include <QHeaderView>
#include <QRegularExpression>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonParseError>
#include <QJsonValue>
#include <QScrollBar>
#include <QVBoxLayout>
#include <algorithm>
#include <vector>
#include <sys/statvfs.h>

#include "common/util.h"
#include "selfdrive/ui/qt/widgets/input.h"

namespace {

QJsonDocument parseJson(const std::string &raw) {
  QJsonParseError err;
  QJsonDocument doc = QJsonDocument::fromJson(QByteArray::fromStdString(raw), &err);
  if (err.error != QJsonParseError::NoError) {
    return QJsonDocument();
  }
  return doc;
}

QString formatDuration(double seconds) {
  if (seconds <= 0.0) return QString();
  if (seconds < 60.0) return QString::number(seconds, 'f', 1) + QObject::tr("s");
  int mins = static_cast<int>(seconds / 60.0);
  double rem = seconds - mins * 60.0;
  return QString("%1m %2s").arg(mins).arg(rem, 0, 'f', 0);
}

}  // namespace

ForkSwapPanel::ForkSwapPanel(QWidget *parent, bool show_back_button)
    : ListWidget(parent), back_control(nullptr), state_label(nullptr),
      message_label(nullptr), disk_label(nullptr), fork_tree(nullptr), log_view(nullptr), refresh_control(nullptr),
      check_updates_control(nullptr), switch_control(nullptr), delete_control(nullptr), update_control(nullptr),
      clone_control(nullptr), view_log_control(nullptr), status_refresh_pending(false) {
  setContentsMargins(0, 0, 0, 0);
  setSpacing(25);

  if (show_back_button) {
    back_control = new ButtonControl(tr("Return to Home"), tr("BACK"), tr("Close the fork manager and go back."), this);
    addItem(back_control);
    connect(back_control, &ButtonControl::clicked, this, &ForkSwapPanel::back);
  }

  addItem(buildStatusCard());
  addItem(buildInstructionCard());

  clone_control = new ButtonControl(tr("Clone a new fork"), tr("CLONE"),
                                    tr("Add a fork by cloning from a Git repository. Perform this while offroad."), this);
  addItem(clone_control);
  connect(clone_control, &ButtonControl::clicked, this, &ForkSwapPanel::cloneFork);

  switch_control = new ButtonControl(tr("Switch active fork"), tr("SWITCH"),
                                     tr("Make the selected fork active and reboot when finished."), this);
  addItem(switch_control);
  connect(switch_control, &ButtonControl::clicked, this, &ForkSwapPanel::switchFork);

  update_control = new ButtonControl(tr("Update selected fork"), tr("UPDATE"),
                                     tr("Fetch and merge changes from the origin for the selected fork."), this);
  addItem(update_control);
  connect(update_control, &ButtonControl::clicked, this, &ForkSwapPanel::updateFork);

  rename_control = new ButtonControl(tr("Rename selected fork"), tr("RENAME"),
                                     tr("Rename the selected fork."), this);
  addItem(rename_control);
  connect(rename_control, &ButtonControl::clicked, this, &ForkSwapPanel::renameFork);

  repair_overlay_control = new ButtonControl(tr("Repair overlay"), tr("REPAIR"),
                                             tr("Reapply the ForkSwap overlay files to the current fork."), this);
  addItem(repair_overlay_control);
  repair_overlay_control->setVisible(false);
  connect(repair_overlay_control, &ButtonControl::clicked, this, &ForkSwapPanel::repairOverlay);

  delete_control = new ButtonControl(tr("Delete selected fork"), tr("DELETE"),
                                     tr("Remove the selected fork from local storage. This cannot be undone."), this);
  addItem(delete_control);
  connect(delete_control, &ButtonControl::clicked, this, &ForkSwapPanel::deleteFork);

  refresh_control = new ButtonControl(tr("Refresh status"), tr("REFRESH"),
                                      tr("Fetch the latest status information for all tracked forks."), this);
  addItem(refresh_control);
  connect(refresh_control, &ButtonControl::clicked, [this]() { refreshStatus(true, false); });

  check_updates_control = new ButtonControl(tr("Check for remote updates"), tr("CHECK"),
                                            tr("Request a full status update and check each fork for upstream changes."), this);
  addItem(check_updates_control);
  connect(check_updates_control, &ButtonControl::clicked, [this]() {
    check_updates_control->setEnabled(false);
    refreshStatus(true, true);
    QTimer::singleShot(30000, [this]() { check_updates_control->setEnabled(true); });
  });

  view_log_control = new ButtonControl(tr("View forkswap log"), tr("OPEN"),
                                       tr("Open the full /data/fork_swap.log history."), this);
  addItem(view_log_control);
  connect(view_log_control, &ButtonControl::clicked, this, &ForkSwapPanel::showFullLog);

  addItem(buildForkListCard());
  addItem(buildLogCard());

  timer = new QTimer(this);
  connect(timer, &QTimer::timeout, this, &ForkSwapPanel::tick);
  timer->start(2000);

  manualRefresh();
}

QWidget *ForkSwapPanel::buildStatusCard() {
  QFrame *card = new QFrame(this);
  card->setObjectName("forkswap_card");
  card->setStyleSheet(R"(
    #forkswap_card {
      background-color: #151515;
      border-radius: 24px;
    }
    #forkswap_card QLabel {
      color: #FFFFFF;
    }
  )");

  QVBoxLayout *layout = new QVBoxLayout(card);
  layout->setContentsMargins(48, 36, 48, 36);
  layout->setSpacing(14);

  state_label = new QLabel(tr("IDLE"), card);
  state_label->setStyleSheet("font-size: 72px; font-weight: 600;");
  layout->addWidget(state_label);

  message_label = new QLabel(tr("No requests pending."), card);
  message_label->setWordWrap(true);
  message_label->setStyleSheet("font-size: 44px; color: #D0D0D0;");
  layout->addWidget(message_label);

  progress_label = new QLabel(card);
  progress_label->setWordWrap(true);
  progress_label->setStyleSheet("font-size: 38px; color: #9E9E9E;");
  progress_label->setVisible(false);
  layout->addWidget(progress_label);

  overlay_label = new QLabel(card);
  overlay_label->setWordWrap(true);
  overlay_label->setStyleSheet("font-size: 34px; color: #AA8800;");
  overlay_label->setVisible(false);
  layout->addWidget(overlay_label);

  disk_label = new QLabel(card);
  disk_label->setStyleSheet("font-size: 36px; color: #9E9E9E;");
  layout->addWidget(disk_label);

  return card;
}

QWidget *ForkSwapPanel::buildInstructionCard() {
  QFrame *card = new QFrame(this);
  card->setObjectName("forkswap_card");
  card->setStyleSheet(R"(
    #forkswap_card {
      background-color: #151515;
      border-radius: 24px;
    }
    #forkswap_card QLabel {
      color: #BDBDBD;
    }
  )");

  QVBoxLayout *layout = new QVBoxLayout(card);
  layout->setContentsMargins(48, 30, 48, 30);
  layout->setSpacing(8);

  QLabel *title = new QLabel(tr("Manage forks while offroad."), card);
  title->setStyleSheet("font-size: 48px; font-weight: 500; color: #FFFFFF;");
  layout->addWidget(title);

  QLabel *help = new QLabel(tr("Clone adds a new fork from Git. Select a fork to Switch, Update, or Delete."), card);
  help->setWordWrap(true);
  help->setStyleSheet("font-size: 40px;");
  layout->addWidget(help);

  return card;
}

QWidget *ForkSwapPanel::buildForkListCard() {
  QFrame *card = new QFrame(this);
  card->setObjectName("forkswap_card");
  card->setStyleSheet(R"(
    #forkswap_card {
      background-color: #151515;
      border-radius: 24px;
    }
    #forkswap_card QLabel {
      color: #FFFFFF;
    }
    QTreeWidget#forkswap_tree {
      background-color: #202020;
      border-radius: 12px;
      font-size: 36px;
    }
    QTreeWidget#forkswap_tree::item {
      height: 72px;
    }
    QTreeWidget#forkswap_tree::item:alternate {
      background-color: #272727;
    }
    QTreeView::item:selected {
      background-color: #2F4F8F;
      color: #FFFFFF;
    }
    QHeaderView::section {
      background-color: transparent;
      color: #BDBDBD;
      font-size: 34px;
    }
  )");

  QVBoxLayout *layout = new QVBoxLayout(card);
  layout->setContentsMargins(48, 30, 48, 36);
  layout->setSpacing(18);

  QLabel *title = new QLabel(tr("Managed forks"), card);
  title->setStyleSheet("font-size: 52px; font-weight: 600;");
  layout->addWidget(title);

  fork_tree = new QTreeWidget(card);
  fork_tree->setObjectName("forkswap_tree");
  fork_tree->setColumnCount(4);
  QStringList headers{tr("Fork"), tr("Branch"), tr("Status"), tr("Origin")};
  fork_tree->setHeaderLabels(headers);
  fork_tree->setSelectionMode(QAbstractItemView::SingleSelection);
  fork_tree->setRootIsDecorated(false);
  fork_tree->setUniformRowHeights(true);
  fork_tree->setMinimumHeight(500);
  fork_tree->setAlternatingRowColors(true);
  fork_tree->header()->setSectionResizeMode(QHeaderView::Stretch);
  layout->addWidget(fork_tree);

  return card;
}

QWidget *ForkSwapPanel::buildLogCard() {
  QFrame *card = new QFrame(this);
  card->setObjectName("forkswap_card");
  card->setStyleSheet(R"(
    #forkswap_card {
      background-color: #151515;
      border-radius: 24px;
    }
    #forkswap_card QLabel {
      color: #FFFFFF;
    }
    QTextEdit#forkswap_log {
      background-color: #202020;
      border-radius: 12px;
      font-size: 32px;
      font-family: monospace;
      color: #DADADA;
    }
  )");

  QVBoxLayout *layout = new QVBoxLayout(card);
  layout->setContentsMargins(48, 30, 48, 36);
  layout->setSpacing(18);

  QLabel *title = new QLabel(tr("Recent activity"), card);
  title->setStyleSheet("font-size: 52px; font-weight: 600;");
  layout->addWidget(title);

  log_view = new QTextEdit(card);
  log_view->setObjectName("forkswap_log");
  log_view->setReadOnly(true);
  log_view->setMinimumHeight(720);
  log_view->setVerticalScrollBarPolicy(Qt::ScrollBarAsNeeded);
  if (QScrollBar *scroll = log_view->verticalScrollBar()) {
    scroll->setStyleSheet(R"(
      QScrollBar:vertical {
        width: 40px;
        background: #1C1C1C;
        margin: 8px 8px 8px 8px;
        border-radius: 18px;
      }
      QScrollBar::handle:vertical {
        background: #5A5A5A;
        border-radius: 18px;
        min-height: 80px;
      }
      QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {
        height: 0px;
        width: 0px;
      }
    )");
    scroll->setSingleStep(12);
  }
  layout->addWidget(log_view);

  return card;
}

void ForkSwapPanel::manualRefresh() {
  refreshStatus(true, false);
  updateDiskSpace();
}

void ForkSwapPanel::tick() {
  refreshStatus(false, false);
  updateDiskSpace();
}

void ForkSwapPanel::refreshStatus(bool force_request, bool check_updates) {
  if (force_request) {
    QJsonObject options;
    if (check_updates) {
      options.insert("check_updates", true);
    }
    queueAction("status", options);
  }

  std::string raw = params.get("ForkSwapStatus");
  if (raw.empty()) {
    state_label->setText(tr("Unavailable"));
    message_label->setText(tr("No status has been reported yet."));
    return;
  }

  QJsonDocument doc = parseJson(raw);
  if (!doc.isObject()) {
    state_label->setText(tr("Error"));
    message_label->setText(tr("Unable to parse forkswap status."));
    return;
  }
  applyStatus(doc.object());
}

void ForkSwapPanel::applyStatus(const QJsonObject &status_obj) {
  QString state = status_obj.value("state").toString("idle");
  QString message = status_obj.value("message").toString();
  double duration = status_obj.value("duration").toDouble(-1.0);
  QString duration_text = formatDuration(duration);

  QString action = status_obj.value("action").toString();
  QString header = state.toUpper();
  if (!action.isEmpty()) {
    header += QString(" • %1").arg(action.toUpper());
  }
  if (!duration_text.isEmpty()) {
    header += QString(" (%1)").arg(duration_text);
  }
  state_label->setText(header);
  message_label->setText(message.isEmpty() ? tr("Ready.") : friendlyForkText(message));

  QJsonObject detail = status_obj.value("detail").toObject();

  if (!detail.isEmpty()) {
    if (detail.contains("forks")) {
      updateForkList(detail.value("forks").toArray());
    }
    if (detail.contains("current_fork")) {
      QString current = detail.value("current_fork").toString();
      for (int i = 0; i < fork_tree->topLevelItemCount(); ++i) {
        auto *item = fork_tree->topLevelItem(i);
        bool active = (item->data(0, Qt::UserRole).toString() == current);
        item->setForeground(0, active ? QBrush(Qt::green) : QBrush(Qt::white));
      }
    }
  }

  updateLogView(status_obj.value("log_tail").toArray());

  QString request_id = status_obj.value("request_id").toString();
  if (!request_id.isEmpty()) {
    last_request_id = request_id;
  }

  double started_at = status_obj.value("started_at").toDouble(0.0);
  double reported_duration = status_obj.value("duration").toDouble(-1.0);
  double updated_at = status_obj.value("updated_at").toDouble(0.0);
  double elapsed = reported_duration >= 0.0 ? reported_duration : ((started_at > 0.0 && updated_at > started_at) ? (updated_at - started_at) : -1.0);

  QJsonObject request = detail.value("request").toObject();
  QString fork = request.value("fork").toString();
  QString branch = request.value("branch").toString();

  if (state == "error") {
    message_label->setStyleSheet("font-size: 44px; color: #ff6666;");
  } else if (state == "running") {
    message_label->setStyleSheet("font-size: 44px; color: #f0c674;");
  } else {
    message_label->setStyleSheet("font-size: 44px; color: #D0D0D0;");
  }

  QStringList progress_bits;
  if (!action.isEmpty()) {
    progress_bits << tr("Action %1").arg(action);
  }
  if (!fork.isEmpty()) {
    progress_bits << tr("Fork %1").arg(friendlyForkName(fork));
  }
  if (!branch.isEmpty()) {
    progress_bits << tr("Branch %1").arg(branch);
  }
  if (elapsed >= 0.0) {
    progress_bits << tr("Elapsed %1").arg(formatDuration(elapsed));
  }
  QString trimmed_log = last_log_line.trimmed();
  if ((state == "running" || state == "error") && !trimmed_log.isEmpty()) {
    if (trimmed_log.length() > 200) {
      trimmed_log = trimmed_log.left(197) + QStringLiteral("…");
    }
    progress_bits << tr("Last log: %1").arg(friendlyForkText(trimmed_log));
  }

  if (!progress_bits.isEmpty() && progress_label != nullptr) {
    progress_label->setText(progress_bits.join(" • "));
    progress_label->setVisible(true);
  } else if (progress_label != nullptr) {
    progress_label->clear();
    progress_label->setVisible(false);
  }

  if (overlay_label != nullptr) {
    QString overlay_state = status_obj.value("overlay_status").toString();
    if (overlay_state.isEmpty()) {
      overlay_state = detail.value("overlay_status").toString();
    }
    if (overlay_state == "ok" || overlay_state.isEmpty()) {
      overlay_label->setVisible(false);
      overlay_label->clear();
      if (repair_overlay_control) {
        repair_overlay_control->setVisible(false);
        repair_overlay_control->setEnabled(true);
      }
    } else if (overlay_state == "repairing") {
      overlay_label->setText(tr("Overlay: attempting repair..."));
      overlay_label->setStyleSheet("font-size: 34px; color: #FFA726;");
      overlay_label->setVisible(true);
      if (repair_overlay_control) {
        repair_overlay_control->setVisible(false);
        repair_overlay_control->setEnabled(false);
      }
    } else {
      QString overlay_message;
      if (overlay_state == "repair_failed") {
        overlay_message = tr("Overlay repair failed. Tap REPAIR to retry.");
      } else if (overlay_state == "repair_incomplete") {
        overlay_message = tr("Overlay may be incomplete. Tap REPAIR to attempt a fix.");
      } else {
        overlay_message = tr("Overlay warning: %1").arg(friendlyForkText(overlay_state));
      }
      overlay_label->setText(overlay_message);
      overlay_label->setStyleSheet("font-size: 34px; color: #FFA726;");
      overlay_label->setVisible(true);
      if (repair_overlay_control) {
        repair_overlay_control->setVisible(true);
        repair_overlay_control->setEnabled(true);
      }
    }
  }

  bool busy = (state == "running");
  for (ButtonControl *control : {clone_control, switch_control, delete_control, update_control, rename_control, repair_overlay_control}) {
    if (control != nullptr) {
      control->setEnabled(!busy);
    }
  }
  for (ButtonControl *control : {refresh_control, check_updates_control}) {
    if (control != nullptr) {
      control->setEnabled(!busy);
    }
  }
  if (timer) {
    int target_interval = busy ? 500 : 2000;
    if (timer->interval() != target_interval) {
      timer->setInterval(target_interval);
    }
  }

  if (status_refresh_pending && state != "running" && action != "status" && request_id == last_request_id) {
    status_refresh_pending = false;
    QTimer::singleShot(0, this, [this]() { refreshStatus(true, false); });
  }
}

void ForkSwapPanel::updateForkList(const QJsonArray &forks) {
  fork_tree->clear();
  for (const QJsonValue &val : forks) {
    QJsonObject obj = val.toObject();
    QString name = obj.value("name").toString();
    QString branch = obj.value("branch").toString();
    QString origin = obj.value("url").toString();
    bool has_update = obj.value("has_update").toBool(false);
    bool is_current = obj.value("is_current").toBool(false);

    QString status = is_current ? tr("Active") : tr("Available");
    if (has_update) {
      status += tr(" (Update)");
    }

    auto *item = new QTreeWidgetItem(fork_tree);
    item->setText(0, friendlyForkName(name));
    item->setText(1, branch);
    item->setText(2, status);
    item->setText(3, origin);
    item->setData(0, Qt::UserRole, name);
    if (is_current) {
      item->setForeground(0, QBrush(Qt::green));
    }
  }

  if (fork_tree->topLevelItemCount() > 0 && !fork_tree->currentItem()) {
    fork_tree->setCurrentItem(fork_tree->topLevelItem(0));
  }
}

void ForkSwapPanel::updateLogView(const QJsonArray &log_tail) {
  QStringList lines;
  lines.reserve(log_tail.size());
  for (const QJsonValue &val : log_tail) {
    lines.append(val.toString());
  }
  if (!lines.isEmpty()) {
    last_log_line = lines.constLast();
  } else {
    last_log_line.clear();
  }
  QScrollBar *scroll = log_view->verticalScrollBar();
  int old_value = scroll->value();
  int old_max = scroll->maximum();
  bool slider_down = scroll->isSliderDown();
  int threshold = std::max(10, scroll->pageStep());
  bool was_at_bottom = !slider_down && (old_max - old_value) <= threshold;

  const QString text = lines.join('\n');
  if (log_view->toPlainText() != text) {
    log_view->setPlainText(text);
  }

  int new_max = scroll->maximum();
  if (was_at_bottom) {
    scroll->setValue(new_max);
  } else {
    int delta = new_max - old_max;
    int new_value = old_value + delta;
    if (new_value < 0) new_value = 0;
    if (new_value > new_max) new_value = new_max;
    scroll->setValue(new_value);
  }
}

void ForkSwapPanel::showFullLog() {
  constexpr int max_chars = 200000;
  std::string raw = util::read_file("/data/fork_swap.log");
  if (raw.empty()) {
    showToast(tr("Forkswap log is empty."));
    return;
  }
  if ((int)raw.size() > max_chars) {
    raw = raw.substr(raw.size() - max_chars);
  }
  QString text = QString::fromStdString(raw).toHtmlEscaped();
  ConfirmationDialog::rich(QString("<pre>%1</pre>").arg(text), this);
}

QString ForkSwapPanel::selectedFork() const {
  auto *item = fork_tree->currentItem();
  if (!item) return QString();
  return item->data(0, Qt::UserRole).toString();
}

void ForkSwapPanel::cloneFork() {
  QString fork, url, branch;
  QJsonObject options = promptCloneOptions(&fork, &url, &branch);
  if (fork.isEmpty() || url.isEmpty()) {
    return;
  }
  queueAction("clone", options, fork, url, branch);
}

QJsonObject ForkSwapPanel::promptCloneOptions(QString *out_fork, QString *out_url, QString *out_branch) {
  InputDialog name_dialog(tr("Fork Name"), this, tr("Enter a short name for the fork"));
  name_dialog.setMinLength(1);
  name_dialog.setMaxLength(DEFAULT_MAX_LENGTH);
  if (name_dialog.exec() != QDialog::Accepted) {
    return QJsonObject();
  }
  const QString fork = name_dialog.text().trimmed();
  if (fork.isEmpty()) {
    return QJsonObject();
  }

  InputDialog url_dialog(tr("Git URL"), this, tr("Provide a full Git HTTPS URL"));
  url_dialog.setMinLength(1);
  url_dialog.setMaxLength(DEFAULT_MAX_LENGTH);
  if (url_dialog.exec() != QDialog::Accepted) {
    return QJsonObject();
  }
  const QString url = url_dialog.text().trimmed();
  if (url.isEmpty()) {
    return QJsonObject();
  }
  QString normalized_url = url;
  if (!normalized_url.contains("://")) {
    normalized_url.prepend("https://");
  }
  if (normalized_url.startsWith("http://", Qt::CaseInsensitive)) {
    normalized_url.replace(0, 7, "https://");
  }

  InputDialog branch_dialog(tr("Branch (optional)"), this, tr("Leave blank to use the repository default"));
  branch_dialog.setMinLength(0);
  branch_dialog.setMaxLength(DEFAULT_MAX_LENGTH);
  if (branch_dialog.exec() != QDialog::Accepted) {
    return QJsonObject();
  }
  const QString branch = branch_dialog.text().trimmed();

  struct Option {
    QString label;
    QString value;
  };
  const std::vector<Option> exists_options = {
      {tr("Abort if fork exists"), QStringLiteral("abort")},
      {tr("Overwrite existing fork"), QStringLiteral("overwrite")},
      {tr("Rename existing fork"), QStringLiteral("rename")} };
  QStringList exists_labels;
  for (const auto &opt : exists_options) {
    exists_labels.append(opt.label);
  }
  const QString exists_choice = MultiOptionDialog::getSelection(tr("If a fork with this name already exists"), exists_labels, "", this);
  if (exists_choice.isEmpty()) {
    return QJsonObject();
  }

  const Option *selected_exists = nullptr;
  for (const auto &opt : exists_options) {
    if (opt.label == exists_choice) {
      selected_exists = &opt;
      break;
    }
  }
  if (selected_exists == nullptr) {
    return QJsonObject();
  }

  QString rename_target;
  if (selected_exists->value == QStringLiteral("rename")) {
    InputDialog rename_dialog(tr("Rename Target"), this, tr("Enter a name for the existing fork backup"));
    rename_dialog.setMinLength(1);
    rename_dialog.setMaxLength(DEFAULT_MAX_LENGTH);
    if (rename_dialog.exec() != QDialog::Accepted) {
      return QJsonObject();
    }
    rename_target = rename_dialog.text().trimmed();
    if (rename_target.isEmpty()) {
      return QJsonObject();
    }
  }

  const QStringList reboot_labels{tr("Reboot after clone"), tr("Don't reboot")};
  const QString reboot_choice = MultiOptionDialog::getSelection(tr("Reboot after clone completes?"), reboot_labels, "", this);
  if (reboot_choice.isEmpty()) {
    return QJsonObject();
  }
  const bool reboot = reboot_choice == reboot_labels.first();

  *out_fork = fork;
  *out_url = normalized_url;
  *out_branch = branch;

  QJsonObject options;
  options.insert("reboot", reboot);
  if (selected_exists->value == QStringLiteral("overwrite")) {
    options.insert("on_exists", QStringLiteral("overwrite"));
  } else if (selected_exists->value == QStringLiteral("rename")) {
    options.insert("on_exists", QStringLiteral("rename"));
    options.insert("rename_to", rename_target);
  }
  return options;
}

void ForkSwapPanel::switchFork() {
  QString fork = selectedFork();
  if (fork.isEmpty()) {
    showToast(tr("Select a fork to switch."));
    return;
  }
  if (!ConfirmationDialog::confirm(tr("Switch to '%1'?").arg(friendlyForkName(fork)), tr("Switch"), this)) {
    return;
  }
  queueAction("switch", QJsonObject{{"reboot", true}}, fork);
}

void ForkSwapPanel::deleteFork() {
  QString fork = selectedFork();
  if (fork.isEmpty()) {
    showToast(tr("Select a fork to delete."));
    return;
  }
  if (!ConfirmationDialog::confirm(tr("Delete '%1'? This cannot be undone.").arg(friendlyForkName(fork)), tr("Delete"), this)) {
    return;
  }
  queueAction("delete", QJsonObject{{"confirm", true}}, fork);
}

void ForkSwapPanel::repairOverlay() {
  if (repair_overlay_control != nullptr) {
    repair_overlay_control->setEnabled(false);
  }
  if (overlay_label != nullptr) {
    overlay_label->setText(tr("Overlay: attempting repair..."));
    overlay_label->setStyleSheet("font-size: 34px; color: #FFA726;");
    overlay_label->setVisible(true);
  }
  queueAction("repair_overlay");
}

void ForkSwapPanel::updateFork() {
  QString fork = selectedFork();
  if (fork.isEmpty()) {
    showToast(tr("Select a fork to update."));
    return;
  }
  if (!ConfirmationDialog::confirm(tr("Update '%1' from origin?").arg(friendlyForkName(fork)), tr("Update"), this)) {
    return;
  }
  queueAction("update", QJsonObject{{"accept_local_changes", false}}, fork);
}

void ForkSwapPanel::renameFork() {
  QString fork = selectedFork();
  if (fork.isEmpty()) {
    showToast(tr("Select a fork to rename."));
    return;
  }

  InputDialog rename_dialog(tr("Rename Fork"), this, tr("Enter a new name for %1").arg(friendlyForkName(fork)));
  rename_dialog.setMinLength(1);
  rename_dialog.setMaxLength(DEFAULT_MAX_LENGTH);
  if (rename_dialog.exec() != QDialog::Accepted) {
    return;
  }

  QString new_name = rename_dialog.text().trimmed();
  if (new_name.isEmpty()) {
    return;
  }
  if (new_name.compare(fork, Qt::CaseInsensitive) == 0) {
    showToast(tr("Fork name unchanged."));
    return;
  }

  static QRegularExpression valid_pattern(QStringLiteral("^[A-Za-z0-9_-]+$"));
  if (!valid_pattern.match(new_name).hasMatch()) {
    showToast(tr("Fork names may only use letters, numbers, hyphen, and underscore."));
    return;
  }

  if (!ConfirmationDialog::confirm(tr("Rename '%1' to '%2'?").arg(friendlyForkName(fork), friendlyForkName(new_name)), tr("Rename"), this)) {
    return;
  }

  QJsonObject options;
  options.insert("rename_to", new_name);
  queueAction("rename", options, fork);
}

void ForkSwapPanel::queueAction(const QString &action, const QJsonObject &options, const QString &fork, const QString &url, const QString &branch) {
  QJsonObject payload;
  payload.insert("action", action);
  if (!fork.isEmpty()) payload.insert("fork", fork);
  if (!url.isEmpty()) payload.insert("url", url);
  if (!branch.isEmpty()) payload.insert("branch", branch);
  if (!options.isEmpty()) payload.insert("options", options);

  QString request_id = QString::fromStdString(util::random_string(16));
  payload.insert("request_id", request_id);

  QJsonDocument doc(payload);
  std::string json = doc.toJson(QJsonDocument::Compact).toStdString();
  params.put("ForkSwapPayload", json);
  params.put("ForkSwapAction", request_id.toStdString());
  last_request_id = request_id;

  if (action != "status") {
    message_label->setText(tr("Submitted request %1 (%2).").arg(request_id, action));
    status_refresh_pending = true;
  } else {
    status_refresh_pending = false;
  }
}

void ForkSwapPanel::showToast(const QString &msg) {
  ConfirmationDialog::alert(msg, this);
}

void ForkSwapPanel::back() {
  emit backRequested();
}

void ForkSwapPanel::updateDiskSpace() {
  struct statvfs vfs;
  if (statvfs("/data", &vfs) == 0) {
    uint64_t free_bytes = static_cast<uint64_t>(vfs.f_bsize) * static_cast<uint64_t>(vfs.f_bavail);
    uint64_t total_bytes = static_cast<uint64_t>(vfs.f_bsize) * static_cast<uint64_t>(vfs.f_blocks);
    disk_label->setText(tr("Free space: %1 / %2 (\u2215data)").arg(formatSize(free_bytes), formatSize(total_bytes)));
  } else {
    disk_label->setText(tr("Unable to read disk usage."));
  }
}

QString ForkSwapPanel::friendlyForkName(const QString &name) const {
  if (name.compare(QStringLiteral("stock"), Qt::CaseInsensitive) == 0) {
    return QStringLiteral("james5294");
  }
  return name;
}

QString ForkSwapPanel::friendlyForkText(const QString &text) const {
  QString result = text;
  static QRegularExpression stock_re(QStringLiteral("\\bstock\\b"), QRegularExpression::CaseInsensitiveOption);
  result.replace(stock_re, QStringLiteral("james5294"));
  return result;
}

QString ForkSwapPanel::formatSize(uint64_t bytes) {
  static const char *units[] = {"B", "KB", "MB", "GB", "TB"};
  double value = static_cast<double>(bytes);
  int unit = 0;
  while (value >= 1024.0 && unit < 4) {
    value /= 1024.0;
    ++unit;
  }
  return QString("%1 %2").arg(QString::number(value, 'f', value >= 10.0 ? 0 : 1), units[unit]);
}
