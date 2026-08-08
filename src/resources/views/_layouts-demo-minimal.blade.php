{{--
    Page de démonstration de <x-layouts.minimal> (Story 1.13, T7).

    Support des tests navigateur, absente en production. Elle existe pour que
    l'assertion d'ABSENCE de l'AC2 soit vérifiable sur un document réellement
    rendu par un navigateur, et pas seulement sur une chaîne de HTML.
--}}
<x-layouts.minimal title="Démonstration du layout minimal">
    <div class="space-y-4">
        <h1 id="page-title" class="text-2xl font-medium">Layout minimal</h1>

        <p class="text-text-secondary leading-prose">
            Story&nbsp;1.13. Ni header, ni footer : ce document n'a que son contenu.
        </p>
    </div>
</x-layouts.minimal>
