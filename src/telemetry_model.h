// Silicon LogiX / SLX OrbitLab
// Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
// Author: Marco Pezzullo
// License: Silicon LogiX Evaluation License 1.0. See LICENSE.

/// @file
/// @brief Stable channel rows keep selection and scrolling while native values change.
#pragma once
#include <QAbstractListModel>
#include <QHash>
#include <QVariantList>
class TelemetryModel final : public QAbstractListModel
{
    Q_OBJECT
  public:
    enum Role
    {
        NameRole = Qt::UserRole + 1,
        ValueRole
    };
    explicit TelemetryModel(QObject *parent = nullptr) : QAbstractListModel(parent) {}
    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    void updateChannels(const QVariantList &channels, const QString &runId);

  private:
    struct Row
    {
        QString name;
        QVariant value;
    };
    QList<Row> m_rows;
    QHash<QString, int> m_indices;
    QString m_runId;
};
