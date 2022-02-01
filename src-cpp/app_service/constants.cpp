#include "constants.h"
#include <QDir>
#include <QFileInfo>
#include <QStandardPaths>
#include <QString>

// TODO: merge with constants from backend/


QString Constants::applicationPath(QString path)
{
	return QFileInfo(QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + path).absoluteFilePath();
}

QString Constants::tmpPath(QString path)
{
	return QFileInfo(QStandardPaths::writableLocation(QStandardPaths::TempLocation) + path).absoluteFilePath();
}

QString Constants::cachePath(QString path)
{
	return QFileInfo(QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + path).absoluteFilePath();
}
