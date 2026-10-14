// Silicon LogiX / SLX OrbitLab
// Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
// Author: Marco Pezzullo
// License: Silicon LogiX Evaluation License 1.0. See LICENSE.

/// @file
/// @brief Builds the Windows icon from the product's vector artwork.

#include <QBuffer>
#include <QDataStream>
#include <QFile>
#include <QGuiApplication>
#include <QImage>
#include <QPainter>
#include <QSvgRenderer>
#include <QVector>

/// @brief Renders the product SVG at Windows icon sizes and writes an ICO with PNG
/// payloads.
int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    if (app.arguments().size() != 3)
        return 2;

    QSvgRenderer renderer(app.arguments().at(1));
    if (!renderer.isValid())
        return 3;

    const QVector<int> sizes{16, 24, 32, 48, 64, 128, 256};
    QVector<QByteArray> images;
    images.reserve(sizes.size());
    for (int size : sizes)
    {
        QImage image(size, size, QImage::Format_ARGB32);
        image.fill(Qt::transparent);
        QPainter painter(&image);
        painter.setRenderHint(QPainter::Antialiasing);
        renderer.render(&painter);
        painter.end();
        QByteArray png;
        QBuffer buffer(&png);
        buffer.open(QIODevice::WriteOnly);
        if (!image.save(&buffer, "PNG"))
            return 4;
        images.append(png);
    }

    QFile output(app.arguments().at(2));
    if (!output.open(QIODevice::WriteOnly))
        return 5;
    // ICO offsets address complete PNG payloads. An encoded dimension of zero
    // represents 256 pixels in the ICO directory.
    QDataStream stream(&output);
    stream.setByteOrder(QDataStream::LittleEndian);
    stream << quint16(0) << quint16(1) << quint16(images.size());
    quint32 offset = 6 + quint32(images.size()) * 16;
    for (int index = 0; index < sizes.size(); ++index)
    {
        const int size = sizes.at(index);
        stream << quint8(size == 256 ? 0 : size) << quint8(size == 256 ? 0 : size);
        stream << quint8(0) << quint8(0) << quint16(1) << quint16(32);
        stream << quint32(images.at(index).size()) << offset;
        offset += quint32(images.at(index).size());
    }
    for (const QByteArray &png : images)
    {
        if (output.write(png) != png.size())
            return 6;
    }
    output.close();
    return output.error() == QFile::NoError ? 0 : 7;
}
