#ifndef VIEW_H
#define VIEW_H

#include <QObject>

namespace Modules
{
namespace Main
{

class View : public QObject
{
    Q_OBJECT

public:
    explicit View(QObject* parent = nullptr);
    ~View() = default;

    void load();
signals:
    void viewLoaded();
};
} // namespace Main
} // namespace Modules

#endif // VIEW_H

