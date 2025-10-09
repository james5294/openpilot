#pragma once

#include <QJsonArray>
#include <QJsonObject>
#include <QLabel>
#include <QTextEdit>
#include <QTimer>
#include <QTreeWidget>

#include "common/params.h"
#include "selfdrive/ui/qt/widgets/controls.h"

class ButtonControl;

class ForkSwapPanel : public ListWidget {
  Q_OBJECT

public:
  explicit ForkSwapPanel(QWidget *parent = nullptr, bool show_back_button = false);
  void manualRefresh();

signals:
  void backRequested();

private slots:
  void tick();
  void refreshStatus(bool force_request = false, bool check_updates = false);
  void cloneFork();
  void switchFork();
  void deleteFork();
  void updateFork();
  void back();

private:
  void queueAction(const QString &action, const QJsonObject &options = QJsonObject(), const QString &fork = QString(), const QString &url = QString(), const QString &branch = QString());
  void applyStatus(const QJsonObject &status_obj);
  void updateForkList(const QJsonArray &forks);
  void updateLogView(const QJsonArray &log_tail);
  QString selectedFork() const;
  void showToast(const QString &msg);
  QJsonObject promptCloneOptions(QString *out_fork, QString *out_url, QString *out_branch);
  QWidget *buildStatusCard();
  QWidget *buildInstructionCard();
  QWidget *buildForkListCard();
  QWidget *buildLogCard();
  void updateDiskSpace();
  static QString formatSize(uint64_t bytes);

  Params params;
  ButtonControl *back_control;
  QLabel *state_label;
  QLabel *message_label;
  QLabel *disk_label;
  QTreeWidget *fork_tree;
  QTextEdit *log_view;
  ButtonControl *refresh_control;
  ButtonControl *check_updates_control;
  ButtonControl *switch_control;
  ButtonControl *delete_control;
  ButtonControl *update_control;
  ButtonControl *clone_control;
  QTimer *timer;
  QString last_request_id;
};
