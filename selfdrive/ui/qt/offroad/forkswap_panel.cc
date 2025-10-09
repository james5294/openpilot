#include "selfdrive/ui/qt/offroad/forkswap_panel.h"

#include <QHeaderView>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonParseError>
#include <QJsonValue>
#include <QPlainTextEdit>
#include <QScrollBar>
#include <QVBoxLayout>
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

ForkSwapPanel::ForkSwapPanel(QWidget *parent) : QWidget(parent) {
  QVBoxLayout *layout = new QVBoxLayout(this);
  layout->setContentsMargins(20, 20, 20, 20);
  layout->setSpacing(20);

  QHBoxLayout *header = new QHBoxLayout();
  back_button = new QPushButton(tr("Back"));
  back_button->setFixedWidth(200);
  header->addWidget(back_button);
  header->addStretch();

  state_label = new QLabel(tr("Idle"));
  state_label->setStyleSheet("font-size: 46px; font-weight: 600;");
  header->addWidget(state_label, 0, Qt::AlignRight);

  layout->addLayout(header);

  message_label = new QLabel(tr("No requests pending."));
  message_label->setWordWrap(true);
  message_label->setStyleSheet("font-size: 36px;");
  layout->addWidget(message_label);

  help_label = new QLabel(tr("Clone adds a new fork from Git. Select a fork to Switch, Update, or Delete. Actions should be performed offroad."));
  help_label->setWordWrap(true);
  help_label->setStyleSheet("font-size: 28px; color: #B0B0B0;");
  layout->addWidget(help_label);

  fork_tree = new QTreeWidget(this);
  fork_tree->setColumnCount(4);
  QStringList headers{tr("Fork"), tr("Branch"), tr("Status"), tr("Origin")};
  fork_tree->setHeaderLabels(headers);
  fork_tree->setSelectionMode(QAbstractItemView::SingleSelection);
  fork_tree->setRootIsDecorated(false);
  fork_tree->setUniformRowHeights(true);
  fork_tree->setMinimumHeight(400);
  fork_tree->header()->setSectionResizeMode(QHeaderView::Stretch);
  fork_tree->setAlternatingRowColors(true);
  layout->addWidget(fork_tree, 1);

  QHBoxLayout *button_row = new QHBoxLayout();
  clone_button = new QPushButton(tr("Clone"));
  switch_button = new QPushButton(tr("Switch"));
  delete_button = new QPushButton(tr("Delete"));
  update_button = new QPushButton(tr("Update"));
  refresh_button = new QPushButton(tr("Refresh"));
  check_updates_button = new QPushButton(tr("Check Updates"));

  clone_button->setToolTip(tr("Clone a new fork from a Git repository"));
  switch_button->setToolTip(tr("Switch the active fork"));
  delete_button->setToolTip(tr("Delete the selected fork"));
  update_button->setToolTip(tr("Fetch and merge updates for the selected fork"));
  refresh_button->setToolTip(tr("Refresh fork list using cached status"));
  check_updates_button->setToolTip(tr("Refresh and check each fork for remote updates"));

  for (QPushButton *btn : {clone_button, switch_button, delete_button, update_button, refresh_button, check_updates_button}) {
    btn->setMinimumWidth(180);
    button_row->addWidget(btn);
  }
  button_row->addStretch();
  layout->addLayout(button_row);

  disk_label = new QLabel(this);
  disk_label->setStyleSheet("font-size: 28px; color: #CCCCCC;");
  layout->addWidget(disk_label);

  log_view = new QTextEdit(this);
  log_view->setReadOnly(true);
  log_view->setMinimumHeight(180);
  log_view->setStyleSheet("font-family: monospace;");
  layout->addWidget(log_view);

  setStyleSheet(R"(
    ForkSwapPanel {
      background-color: black;
      color: white;
    }
    QPushButton {
      padding: 12px 24px;
      border-radius: 6px;
      background-color: #404040;
      font-size: 32px;
    }
    QPushButton:pressed {
      background-color: #606060;
    }
    QTreeWidget {
      background-color: #202020;
      border-radius: 6px;
      font-size: 30px;
    }
    QTextEdit {
      background-color: #202020;
      border-radius: 6px;
      font-size: 28px;
    }
  )");

  connect(back_button, &QPushButton::clicked, this, &ForkSwapPanel::back);
  connect(refresh_button, &QPushButton::clicked, [this]() { refreshStatus(true, false); });
  connect(check_updates_button, &QPushButton::clicked, [this]() {
    check_updates_button->setEnabled(false);
    refreshStatus(true, true);
    QTimer::singleShot(30000, [this]() { check_updates_button->setEnabled(true); });
  });
  connect(clone_button, &QPushButton::clicked, this, &ForkSwapPanel::cloneFork);
  connect(switch_button, &QPushButton::clicked, this, &ForkSwapPanel::switchFork);
  connect(delete_button, &QPushButton::clicked, this, &ForkSwapPanel::deleteFork);
  connect(update_button, &QPushButton::clicked, this, &ForkSwapPanel::updateFork);

  timer = new QTimer(this);
  connect(timer, &QTimer::timeout, this, &ForkSwapPanel::tick);
  timer->start(2000);

  manualRefresh();
}

void ForkSwapPanel::manualRefresh() {
  refreshStatus(false, false);
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

  QString header = state.toUpper();
  if (!duration_text.isEmpty()) {
    header += QString(" (%1)").arg(duration_text);
  }
  state_label->setText(header);
  message_label->setText(message.isEmpty() ? tr("Ready.") : message);

  if (status_obj.contains("detail")) {
    QJsonObject detail = status_obj.value("detail").toObject();
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

  if (state == "error") {
    message_label->setStyleSheet("color: #ff6666; font-size: 36px;");
  } else if (state == "running") {
    message_label->setStyleSheet("color: #f0c674; font-size: 36px;");
  } else {
    message_label->setStyleSheet("color: white; font-size: 36px;");
  }

  bool busy = (state == "running");
  for (QPushButton *btn : {clone_button, switch_button, delete_button, update_button}) {
    btn->setEnabled(!busy);
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
    item->setText(0, name);
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
  log_view->setPlainText(lines.join('\n'));
  log_view->verticalScrollBar()->setValue(log_view->verticalScrollBar()->maximum());
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
  if (name_dialog.exec() != QDialog::Accepted) {
    return QJsonObject();
  }
  const QString fork = name_dialog.text().trimmed();
  if (fork.isEmpty()) {
    return QJsonObject();
  }

  InputDialog url_dialog(tr("Git URL"), this, tr("Provide a full Git HTTPS URL"));
  url_dialog.setMinLength(1);
  if (url_dialog.exec() != QDialog::Accepted) {
    return QJsonObject();
  }
  const QString url = url_dialog.text().trimmed();
  if (url.isEmpty()) {
    return QJsonObject();
  }

  InputDialog branch_dialog(tr("Branch (optional)"), this, tr("Leave blank to use the repository default"));
  branch_dialog.setMinLength(0);
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
  *out_url = url;
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
  if (!ConfirmationDialog::confirm(tr("Switch to '%1'?").arg(fork), tr("Switch"), this)) {
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
  if (!ConfirmationDialog::confirm(tr("Delete '%1'? This cannot be undone.").arg(fork), tr("Delete"), this)) {
    return;
  }
  queueAction("delete", QJsonObject{{"confirm", true}}, fork);
}

void ForkSwapPanel::updateFork() {
  QString fork = selectedFork();
  if (fork.isEmpty()) {
    showToast(tr("Select a fork to update."));
    return;
  }
  if (!ConfirmationDialog::confirm(tr("Update '%1' from origin?").arg(fork), tr("Update"), this)) {
    return;
  }
  queueAction("update", QJsonObject{{"accept_local_changes", false}}, fork);
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

  message_label->setText(tr("Submitted request %1 (%2).").arg(request_id, action));
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
