#include "view.h"

namespace Modules
{
namespace Main
{

View::View(QObject* parent)
    : QObject(parent)
{ }

void View::load()
{
    //  At some point, here, we will setup some exposed main module related things.
    emit viewLoaded();
}

} // namespace Main
} // namespace Modules
