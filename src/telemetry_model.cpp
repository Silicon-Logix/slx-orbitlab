// Silicon LogiX / SLX OrbitLab
// Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
// Author: Marco Pezzullo
// License: Silicon LogiX Evaluation License 1.0. See LICENSE.

/// @file
/// @brief Update channel values without replacing the QML list model.
#include "telemetry_model.h"
int TelemetryModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_rows.size();
}
QVariant TelemetryModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_rows.size())
        return {};
    const auto &row = m_rows[index.row()];
    return role == NameRole ? QVariant(row.name) : role == ValueRole ? row.value : QVariant{};
}
QHash<int, QByteArray> TelemetryModel::roleNames() const
{
    return {{NameRole, "channelName"}, {ValueRole, "channelValue"}};
}
void TelemetryModel::updateChannels(const QVariantList &channels, const QString &runId)
{
    if (runId != m_runId)
    {
        m_runId = runId;
        for (auto &row : m_rows)
            row.value = QStringLiteral("—");
        if (!m_rows.isEmpty())
            emit dataChanged(index(0), index(m_rows.size() - 1), {ValueRole});
    }
    for (const auto &entry : channels)
    {
        const auto channel = entry.toMap();
        const auto name = channel.value("name").toString();
        if (name.isEmpty())
            continue;
        const auto value = channel.value("value");
        if (!m_indices.contains(name))
        {
            const int row = m_rows.size();
            beginInsertRows({}, row, row);
            m_indices.insert(name, row);
            m_rows.append({name, value});
            endInsertRows();
        }
        else
        {
            const int row = m_indices.value(name);
            if (m_rows[row].value != value)
            {
                m_rows[row].value = value;
                emit dataChanged(index(row), index(row), {ValueRole});
            }
        }
    }
}
