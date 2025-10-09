#pragma once

#include <QJsonArray>
#include <QJsonObject>
#include <QLabel>
#include <QPushButton>
#include <QTextEdit>
#include <QTimer>
#include <QTreeWidget>
#include <QWidget>

#include "common/params.h"

class ForkSwapPanel : public QWidget {
  Q_OBJECT

public:
  explicit ForkSwapPanel(QWidget *parent = nullptr);
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
  void updateDiskSpace();
  static QString formatSize(uint64_t bytes);

  Params params;
  QLabel *state_label;
  QLabel *message_label;
  QLabel *help_label;
  QLabel *disk_label;
  QTreeWidget *fork_tree;
  QTextEdit *log_view;
  QPushButton *refresh_button;
  QPushButton *check_updates_button;
  QPushButton *switch_button;
  QPushButton *delete_button;
  QPushButton *update_button;
  QPushButton *clone_button;
  QPushButton *back_button;
  QTimer *timer;
  QString last_state;
  QString last_request_id;
};
