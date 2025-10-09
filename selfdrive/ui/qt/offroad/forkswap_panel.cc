#include "selfdrive/ui/qt/offroad/forkswap_panel.h"

#include <QCheckBox>
#include <QComboBox>
#include <QDialog>
#include <QDialogButtonBox>
#include <QFormLayout>
#include <QBrush>
#include <QInputDialog>
#include <QHeaderView>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonValue>
#include <QJsonParseError>
#include <QMessageBox>
#include <QGuiApplication>
#include <QScreen>
#include <QLineEdit>
#include <QPlainTextEdit>
#include <QScrollBar>
#include <QVBoxLayout>
#include <sys/statvfs.h>

#include "common/util.h"

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
  QDialog dialog(this);
  dialog.setWindowTitle(tr("Clone Fork"));
  dialog.setModal(true);
  dialog.setWindowFlags(Qt::Dialog | Qt::FramelessWindowHint);

  dialog.setStyleSheet(R"(
    QDialog {
      background-color: #1a1a1a;
      color: white;
    }
    QLabel {
      font-size: 32px;
      color: white;
    }
    QLineEdit, QComboBox {
      font-size: 32px;
      padding: 12px;
      background-color: #2a2a2a;
      border: 2px solid #404040;
      border-radius: 6px;
      color: white;
      min-height: 50px;
    }
    QCheckBox {
      font-size: 32px;
      spacing: 10px;
    }
    QPushButton {
      font-size: 32px;
      padding: 16px 32px;
      background-color: #404040;
      border-radius: 6px;
      min-width: 150px;
      min-height: 60px;
    }
    QPushButton:pressed {
      background-color: #606060;
    }
  )");

  QFormLayout *form = new QFormLayout(&dialog);
  form->setSpacing(20);
  form->setContentsMargins(40, 40, 40, 40);

  QLineEdit *name_edit = new QLineEdit(&dialog);
  QLineEdit *url_edit = new QLineEdit(&dialog);
  QLineEdit *branch_edit = new QLineEdit(&dialog);
  QCheckBox *reboot_box = new QCheckBox(tr("Reboot after clone"), &dialog);
  reboot_box->setChecked(true);

  QComboBox *exists_mode = new QComboBox(&dialog);
  exists_mode->addItem(tr("Abort if exists"), "abort");
  exists_mode->addItem(tr("Overwrite existing"), "overwrite");
  exists_mode->addItem(tr("Rename existing"), "rename");
  QLineEdit *rename_edit = new QLineEdit(&dialog);
  rename_edit->setPlaceholderText(tr("Existing fork rename target"));
  rename_edit->setEnabled(false);

  QObject::connect(exists_mode, &QComboBox::currentTextChanged, [&](const QString &text) {
    rename_edit->setEnabled(text.contains("Rename"));
  });

  form->addRow(tr("Fork name"), name_edit);
  form->addRow(tr("Git URL"), url_edit);
  form->addRow(tr("Branch (optional)"), branch_edit);
  form->addRow(tr("If fork exists"), exists_mode);
  form->addRow(tr("Rename target"), rename_edit);
  form->addRow(reboot_box);

  QDialogButtonBox *buttons = new QDialogButtonBox(QDialogButtonBox::Ok | QDialogButtonBox::Cancel, &dialog);
  form->addWidget(buttons);
  QObject::connect(buttons, &QDialogButtonBox::accepted, &dialog, &QDialog::accept);
  QObject::connect(buttons, &QDialogButtonBox::rejected, &dialog, &QDialog::reject);

  // Position dialog centered on the available screen geometry
  QRect screenRect = QGuiApplication::primaryScreen()->availableGeometry();
  int targetWidth = std::min(screenRect.width() * 0.8, 1600.0);
  int targetHeight = std::min(screenRect.height() * 0.8, 900.0);
  dialog.resize(targetWidth, targetHeight);
  QPoint centerPoint = screenRect.center() - QPoint(dialog.width() / 2, dialog.height() / 2);
  dialog.move(centerPoint);

  if (dialog.exec() != QDialog::Accepted) {
    return QJsonObject();
  }

  QString name = name_edit->text().trimmed();
  QString url = url_edit->text().trimmed();
  if (name.isEmpty() || url.isEmpty()) {
    showToast(tr("Fork name and URL are required."));
    return QJsonObject();
  }

  *out_fork = name;
  *out_url = url;
  *out_branch = branch_edit->text().trimmed();

  QJsonObject options;
  options.insert("reboot", reboot_box->isChecked());
  QString mode = exists_mode->currentData().toString();
  if (mode == "overwrite") {
    options.insert("on_exists", "overwrite");
  } else if (mode == "rename") {
    options.insert("on_exists", "rename");
    options.insert("rename_to", rename_edit->text().trimmed());
  }
  return options;
}

void ForkSwapPanel::switchFork() {
  QString fork = selectedFork();
  if (fork.isEmpty()) {
    showToast(tr("Select a fork to switch."));
    return;
  }
  if (!confirmAction(tr("Switch Fork"), tr("Switch to '%1'?").arg(fork))) {
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
  if (!confirmAction(tr("Delete Fork"), tr("Delete '%1'? This cannot be undone.").arg(fork))) {
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
  bool proceed = confirmAction(tr("Update Fork"), tr("Update '%1' from origin?").arg(fork));
  if (!proceed) return;
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

bool ForkSwapPanel::confirmAction(const QString &title, const QString &text) {
  QMessageBox msgBox(this);
  msgBox.setWindowTitle(title);
  msgBox.setText(text);
  msgBox.setStandardButtons(QMessageBox::Yes | QMessageBox::No);
  msgBox.setDefaultButton(QMessageBox::No);
  msgBox.setModal(true);

  msgBox.setStyleSheet(R"(
    QMessageBox {
      background-color: #1a1a1a;
      color: white;
      min-width: 800px;
    }
    QLabel {
      font-size: 36px;
      color: white;
      min-width: 600px;
    }
    QPushButton {
      font-size: 32px;
      padding: 16px 32px;
      background-color: #404040;
      border-radius: 6px;
      min-width: 180px;
      min-height: 60px;
    }
    QPushButton:pressed {
      background-color: #606060;
    }
  )");

  return msgBox.exec() == QMessageBox::Yes;
}

void ForkSwapPanel::showToast(const QString &msg) {
  QMessageBox msgBox(this);
  msgBox.setWindowTitle(tr("Forkswap"));
  msgBox.setText(msg);
  msgBox.setStandardButtons(QMessageBox::Ok);
  msgBox.setModal(true);

  msgBox.setStyleSheet(R"(
    QMessageBox {
      background-color: #1a1a1a;
      color: white;
      min-width: 800px;
    }
    QLabel {
      font-size: 36px;
      color: white;
      min-width: 600px;
    }
    QPushButton {
      font-size: 32px;
      padding: 16px 32px;
      background-color: #404040;
      border-radius: 6px;
      min-width: 180px;
      min-height: 60px;
    }
    QPushButton:pressed {
      background-color: #606060;
    }
  )");

  msgBox.exec();
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
